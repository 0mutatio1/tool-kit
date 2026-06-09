import SwiftUI
import WebKit

struct JSONEditorWebView: NSViewRepresentable {
    @Binding var text: String
    @Binding var errorMessage: String?
    var mode: String = "code"

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "jsonEditor")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://cdn.jsdelivr.net"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyTextIfNeeded(text, to: webView)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: JSONEditorWebView
        private var isReady = false
        private var pendingText: String?
        private var lastAppliedText = ""

        init(_ parent: JSONEditorWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            let encodedMode = Self.javascriptStringLiteral(parent.mode)
            webView.evaluateJavaScript("window.ocrmacSetMode(\(encodedMode));")
            applyTextIfNeeded(pendingText ?? parent.text, to: webView)
        }

        func applyTextIfNeeded(_ text: String, to webView: WKWebView) {
            guard text != lastAppliedText else {
                return
            }

            pendingText = text
            guard isReady else {
                return
            }

            lastAppliedText = text
            pendingText = nil
            let encoded = Self.javascriptStringLiteral(text)
            webView.evaluateJavaScript("window.ocrmacSetText(\(encoded));")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard
                let payload = message.body as? [String: Any],
                let type = payload["type"] as? String
            else {
                return
            }

            switch type {
            case "input":
                let text = payload["text"] as? String ?? ""
                lastAppliedText = text
                parent.text = text
                parent.errorMessage = nil
            case "error":
                parent.errorMessage = payload["message"] as? String ?? "JSONEditor could not update the document."
            default:
                break
            }
        }

        private static func javascriptStringLiteral(_ value: String) -> String {
            guard
                let data = try? JSONEncoder().encode(value),
                let encoded = String(data: data, encoding: .utf8)
            else {
                return "\"\""
            }

            return encoded
        }
    }

    private static let html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <link href="https://cdn.jsdelivr.net/npm/jsoneditor@9/dist/jsoneditor.min.css" rel="stylesheet">
      <script src="https://cdn.jsdelivr.net/npm/jsoneditor@9/dist/jsoneditor.min.js"></script>
      <style>
        html, body, #jsoneditor, #fallback {
          width: 100%;
          height: 100%;
          margin: 0;
          background: Canvas;
          color: CanvasText;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        }
        #fallback {
          box-sizing: border-box;
          display: none;
          border: 0;
          padding: 12px;
          resize: none;
          font: 13px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
          outline: none;
        }
      </style>
    </head>
    <body>
      <div id="jsoneditor"></div>
      <textarea id="fallback" spellcheck="false"></textarea>
      <script>
        var editor = null;
        window.isApplyingText = false;
        const fallback = document.getElementById('fallback');
        const container = document.getElementById('jsoneditor');

        function post(payload) {
          window.webkit.messageHandlers.jsonEditor.postMessage(payload);
        }

        function currentText() {
          if (editor) return editor.getText();
          return fallback.value;
        }

        window.ocrmacSetText = function(text) {
          try {
            window.isApplyingText = true;
            if (editor) {
              editor.setText(text || '');
            } else {
              fallback.value = text || '';
            }
            window.isApplyingText = false;
          } catch (error) {
            window.isApplyingText = false;
            post({ type: 'error', message: error.message || String(error) });
          }
        };

        window.ocrmacSetMode = function(mode) {
          if (!editor || !mode) return;
          try {
            editor.setMode(mode);
          } catch (error) {
            post({ type: 'error', message: error.message || String(error) });
          }
        };

        fallback.addEventListener('input', () => {
          post({ type: 'input', text: fallback.value });
        });

        window.addEventListener('load', () => {
          if (window.JSONEditor) {
            editor = new JSONEditor(container, {
              mode: 'code',
              modes: ['tree', 'code', 'text', 'preview'],
              onChange: () => {
                if (!window.isApplyingText) post({ type: 'input', text: currentText() });
              },
              onChangeText: text => {
                if (!window.isApplyingText) post({ type: 'input', text });
              }
            });
            editor.setText('');
          } else {
            container.style.display = 'none';
            fallback.style.display = 'block';
          }
        });
      </script>
    </body>
    </html>
    """
}
