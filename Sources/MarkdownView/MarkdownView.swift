import UIKit
import WebKit

/**
 Markdown View for iOS.
 
 - Note: [How to get height of entire document with javascript](https://stackoverflow.com/questions/1145850/how-to-get-height-of-entire-document-with-javascript)
 */
open class MarkdownView: UIView {
    // 可能需要对外，提供截图的功能
    public var webView: WKWebView?
    
    // 是否跟随系统自动切换 light/dark 风格，默认 true
    public var isFollowSystemUIStyle = true
    
    public var isDarkUIStyle = false {
        didSet {
            reloadMarkdownView()
        }
    }
      
    fileprivate var intrinsicContentHeight: CGFloat? {
        didSet {
            self.invalidateIntrinsicContentSize()
        }
    }

    @objc public var isScrollEnabled: Bool = true {
        didSet {
            webView?.scrollView.isScrollEnabled = isScrollEnabled
        }
    }

    @objc public var onTouchLink: ((URLRequest) -> Bool)?
    @objc public var onRendered: ((CGFloat) -> Void)?
    @objc public var didChangeInterfaceStyle: ((Bool, Error?) -> Void)?

    public convenience init() {
        self.init(frame: .zero)
    }

    override init (frame: CGRect) {
        super.init(frame: frame)
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    open override var intrinsicContentSize: CGSize {
        if let height = self.intrinsicContentHeight {
            return CGSize(width: UIView.noIntrinsicMetric, height: height)
        } else {
            return .zero
        }
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 13.0, *), isFollowSystemUIStyle {
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                isDarkUIStyle = (traitCollection.userInterfaceStyle == .dark)
            }
        }
    }

    @objc public func load(markdown: String?, enableImage: Bool = true) {
        guard let markdown = markdown else { return }

        if let old = self.webView {
            old.navigationDelegate = nil
            old.stopLoading()
            old.removeFromSuperview()
            self.webView = nil
        }

        let primaryBundle = Bundle.markdownViewBundle

        var htmlName = "index"
        if isDarkUIStyle { htmlName = "index_dark" }

        // Ưu tiên tìm trong bundle tài nguyên (SPM: .module, Pods: MarkdownView.bundle)
        var htmlURL: URL? = primaryBundle.url(forResource: htmlName, withExtension: "html")

        // Fallback (giữ tương thích cũ)
        if htmlURL == nil {
            let classBundle = Bundle(for: MarkdownView.self)
            htmlURL = classBundle.url(forResource: htmlName, withExtension: "html", subdirectory: "MarkdownView.bundle")
                ?? Bundle.main.url(forResource: htmlName, withExtension: "html", subdirectory: "MarkdownView.bundle")
        }

        if let url = htmlURL {
            let templateRequest = URLRequest(url: url)

            let escapedMarkdown = self.escape(markdown: markdown) ?? ""
            let imageOption = enableImage ? "true" : "false"
            let script = "window.showMarkdown('\(escapedMarkdown)', \(imageOption));"
            let userScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)

            let controller = WKUserContentController()
            controller.addUserScript(userScript)

            let configuration = WKWebViewConfiguration()
            configuration.userContentController = controller
            let preferences = WKPreferences()
            preferences.javaScriptEnabled = true
            configuration.preferences = preferences
            
            let wv = WKWebView(frame: self.bounds, configuration: configuration)
            wv.scrollView.isScrollEnabled = self.isScrollEnabled
            wv.translatesAutoresizingMaskIntoConstraints = false
            wv.navigationDelegate = self
            wv.isOpaque = false
            wv.backgroundColor = UIColor.systemBackground
            wv.scrollView.backgroundColor = UIColor.systemBackground
            addSubview(wv)
            NSLayoutConstraint.activate([
                wv.topAnchor.constraint(equalTo: self.topAnchor),
                wv.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                wv.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: self.trailingAnchor)
            ])
            wv.isOpaque = false
            wv.scrollView.backgroundColor = #colorLiteral(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
            wv.backgroundColor = #colorLiteral(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)

            self.webView = wv
            wv.load(templateRequest)
        } else {
            // TODO: raise error
        }
    }

    private func escape(markdown: String) -> String? {
        return markdown.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics)
    }
    
    // MARK: - Reload MarkdownView
    private func reloadMarkdownView() {
        guard let webView = self.webView else { return }

        let cssFile = readFileBy(name: (isDarkUIStyle ? "main_dark" : "main"), type: "css")
        let cssStyle = """
            javascript:(function() {
            var parent = document.getElementsByTagName('head').item(0);
            var style = document.createElement('style');
            style.type = 'text/css';
            style.innerHTML = window.atob('\(encodeStringTo64(fromString: cssFile)!)');
            parent.appendChild(style)})()
        """
        webView.evaluateJavaScript(cssStyle) { [weak self] _, error in
            self?.didChangeInterfaceStyle?(self?.isDarkUIStyle ?? false, error)
        }
    }
    
    // MARK: - Encode string to base 64
    private func encodeStringTo64(fromString: String) -> String? {
        let plainData = fromString.data(using: .utf8)
        return plainData?.base64EncodedString(options: [])
    }

    // MARK: - Reading contents of files
    private func readFileBy(name: String, type: String) -> String {
        if let path = Bundle.markdownViewBundle.path(forResource: name, ofType: type) {
            return (try? String(contentsOfFile: path, encoding: .utf8)) ?? "Unkown Error"
        }

        // Fallback: CocoaPods bundle nằm trong host
        if let path = Bundle(for: MarkdownView.self).path(forResource: name, ofType: type, inDirectory: "MarkdownView.bundle") ??
                      Bundle.main.path(forResource: name, ofType: type, inDirectory: "MarkdownView.bundle") {
            return (try? String(contentsOfFile: path, encoding: .utf8)) ?? "Unkown Error"
        }

        return "Failed to find path"
    }
}

extension MarkdownView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = "document.body.scrollHeight;"
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let _ = error { return }

            if let height = result as? CGFloat {
                self?.onRendered?(height)
                self?.intrinsicContentHeight = height
            }
        }
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        switch navigationAction.navigationType {
        case .linkActivated:
            if let onTouchLink = onTouchLink, onTouchLink(navigationAction.request) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        default:
            decisionHandler(.allow)
        }
    }
}

private extension Bundle {
    static var markdownViewBundle: Bundle = {
        #if SWIFT_PACKAGE
        return .module
        #else
        let classBundle = Bundle(for: MarkdownView.self)
        let candidates: [URL?] = [
            classBundle.resourceURL,
            classBundle.bundleURL,
            Bundle.main.resourceURL
        ]
        for candidate in candidates {
            if let url = candidate?.appendingPathComponent("MarkdownView.bundle"),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return classBundle
        #endif
    }()
}
