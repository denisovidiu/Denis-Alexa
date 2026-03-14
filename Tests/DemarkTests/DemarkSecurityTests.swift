//
// DemarkSecurityTests.swift
// Demark
//
// Comparative security tests: checks how Turndown and html-to-md each handle
// hostile HTML inputs (XSS payloads, event handlers, data URIs, CSS injection).
// Neither engine is a sanitizer, but both should at minimum not return
// executable script content in their Markdown output.
//

import Testing
@testable import Demark

// MARK: - Payload catalogue

private enum HostileHTML {
    static let scriptInline = "<p>Hello</p><script>alert('xss')</script>"
    static let scriptSrc = #"<p>Hello</p><script src="https://evil.example/x.js"></script>"#
    static let imgOnerror = #"<img src="x" onerror="alert('xss')">"#
    static let aHrefJavascript = #"<a href="javascript:alert('xss')">click me</a>"#
    static let svgOnload = #"<svg onload="alert('xss')"></svg>"#
    static let styleTag = #"<style>body{background:url(javascript:alert('xss'))}</style><p>Text</p>"#
    static let iframeTag = #"<iframe src="javascript:alert('xss')"></iframe><p>Text</p>"#
    static let formAction = #"<form action="javascript:alert('xss')"><input type="submit"></form><p>Text</p>"#
    static let dataUri = #"<a href="data:text/html,<script>alert('xss')</script>">link</a>"#
    static let encodedScript = "<p>&#60;script&#62;alert(1)&#60;/script&#62;</p>"
    static let nestedQuotes = #"<p onclick='alert("xss")'>text</p>"#
    static let templateInjection = "<p>${7*7}</p><p>{{7*7}}</p>"
}

// MARK: - Helpers

private struct EngineResult {
    let engine: String
    let output: String
    let error: Error?

    var succeeded: Bool { error == nil }
}

@MainActor
private func runBothEngines(html: String) async -> (turndown: EngineResult, htmlToMd: EngineResult) {
    let service = Demark()

    async let td: EngineResult = {
        do {
            let out = try await service.convertToMarkdown(html, options: DemarkOptions(engine: .turndown))
            return EngineResult(engine: "Turndown", output: out, error: nil)
        } catch {
            return EngineResult(engine: "Turndown", output: "", error: error)
        }
    }()

    async let h2md: EngineResult = {
        do {
            let out = try await service.convertToMarkdown(html, options: DemarkOptions(engine: .htmlToMd))
            return EngineResult(engine: "html-to-md", output: out, error: nil)
        } catch {
            return EngineResult(engine: "html-to-md", output: "", error: error)
        }
    }()

    return await (td, h2md)
}

/// Asserts that a result does not contain executable script content.
private func assertNoScriptContent(_ result: EngineResult, sourceLabel: String) {
    let out = result.output.lowercased()
    #expect(!out.contains("<script"), "[\(result.engine)] \(sourceLabel): raw <script> tag leaked into output")
    #expect(!out.contains("alert("), "[\(result.engine)] \(sourceLabel): alert() call leaked into output")
    #expect(!out.contains("javascript:"), "[\(result.engine)] \(sourceLabel): javascript: URI leaked into output")
    #expect(!out.contains("onerror="), "[\(result.engine)] \(sourceLabel): onerror handler leaked into output")
    #expect(!out.contains("onload="), "[\(result.engine)] \(sourceLabel): onload handler leaked into output")
}

// MARK: - Tests

@MainActor
struct DemarkSecurityTests {
    // MARK: Script tags

    @Test("Inline <script> is stripped by both engines")
    func inlineScriptStripped() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.scriptInline)

        print("[Turndown]  inline script → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] inline script → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        assertNoScriptContent(td, sourceLabel: "inline <script>")
        assertNoScriptContent(h2md, sourceLabel: "inline <script>")

        // Visible content must survive
        if td.succeeded { #expect(td.output.contains("Hello"), "[Turndown] visible content lost") }
        if h2md.succeeded { #expect(h2md.output.contains("Hello"), "[html-to-md] visible content lost") }
    }

    @Test("External <script src> is stripped by both engines")
    func externalScriptStripped() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.scriptSrc)

        print("[Turndown]  script src → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] script src → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        assertNoScriptContent(td, sourceLabel: "external <script src>")
        assertNoScriptContent(h2md, sourceLabel: "external <script src>")
    }

    // MARK: Event handlers

    @Test("onerror attribute does not appear in output")
    func imgOnerrorLeaks() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.imgOnerror)

        print("[Turndown]  img onerror → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] img onerror → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        assertNoScriptContent(td, sourceLabel: "img onerror")
        assertNoScriptContent(h2md, sourceLabel: "img onerror")
    }

    @Test("SVG onload attribute does not appear in output")
    func svgOnloadLeaks() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.svgOnload)

        print("[Turndown]  svg onload → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] svg onload → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        assertNoScriptContent(td, sourceLabel: "svg onload")
        assertNoScriptContent(h2md, sourceLabel: "svg onload")
    }

    // MARK: javascript: URIs

    @Test("javascript: href is not preserved as a clickable link")
    func javascriptHref() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.aHrefJavascript)

        print("[Turndown]  javascript: href → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] javascript: href → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        // Link text must survive; javascript: URI must not appear in output
        if td.succeeded {
            #expect(td.output.contains("click me"), "[Turndown] link label lost")
            #expect(!td.output.lowercased().contains("javascript:"), "[Turndown] javascript: URI survived in output")
        }
        if h2md.succeeded {
            #expect(h2md.output.contains("click me"), "[html-to-md] link label lost")
            #expect(!h2md.output.lowercased().contains("javascript:"), "[html-to-md] javascript: URI survived in output")
        }
    }

    @Test("data: URI in href does not survive as a link")
    func dataUriHref() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.dataUri)

        print("[Turndown]  data: href → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] data: href → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        assertNoScriptContent(td, sourceLabel: "data: URI")
        assertNoScriptContent(h2md, sourceLabel: "data: URI")
    }

    // MARK: Style / iframe / form

    @Test("<style> tag content is stripped by both engines")
    func styleTagStripped() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.styleTag)

        print("[Turndown]  style tag → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] style tag → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        if td.succeeded {
            #expect(!td.output.contains("background"), "[Turndown] CSS content leaked into output")
            #expect(td.output.contains("Text"), "[Turndown] visible text lost")
        }
        if h2md.succeeded {
            #expect(!h2md.output.contains("background"), "[html-to-md] CSS content leaked into output")
            #expect(h2md.output.contains("Text"), "[html-to-md] visible text lost")
        }
    }

    @Test("<iframe> tag does not produce executable output")
    func iframeTagHandled() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.iframeTag)

        print("[Turndown]  iframe → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] iframe → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        assertNoScriptContent(td, sourceLabel: "iframe")
        assertNoScriptContent(h2md, sourceLabel: "iframe")
    }

    @Test("<form action=javascript:> does not produce executable output")
    func formActionHandled() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.formAction)

        print("[Turndown]  form action → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] form action → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        assertNoScriptContent(td, sourceLabel: "form action")
        assertNoScriptContent(h2md, sourceLabel: "form action")
    }

    // MARK: Encoding tricks

    @Test("HTML-entity-encoded script tags are decoded and stripped")
    func entityEncodedScript() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.encodedScript)

        print("[Turndown]  entity-encoded → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] entity-encoded → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        // After HTML entity decoding by the engine the decoded script should not execute
        // The raw literal text is acceptable; what is not acceptable is an active <script> node.
        if td.succeeded {
            #expect(!td.output.contains("<script>"), "[Turndown] decoded <script> tag present in output")
        }
        if h2md.succeeded {
            #expect(!h2md.output.contains("<script>"), "[html-to-md] decoded <script> tag present in output")
        }
    }

    @Test("Template-style injection strings pass through as inert text")
    func templateInjectionInert() async {
        let (td, h2md) = await runBothEngines(html: HostileHTML.templateInjection)

        print("[Turndown]  template injection → \(td.succeeded ? td.output : "error: \(td.error!)")")
        print("[html-to-md] template injection → \(h2md.succeeded ? h2md.output : "error: \(h2md.error!)")")

        // Markdown is a plain-text format; template markers should appear as literal text.
        if td.succeeded {
            #expect(td.output.contains("${7*7}") || td.output.contains("7*7"), "[Turndown] template text not preserved")
        }
        if h2md.succeeded {
            #expect(h2md.output.contains("${7*7}") || h2md.output.contains("7*7"), "[html-to-md] template text not preserved")
        }
    }

    // MARK: Engine comparison summary

    @Test("Side-by-side engine output comparison for all payloads")
    func engineComparisonSummary() async {
        let payloads: [(label: String, html: String)] = [
            ("inline-script", HostileHTML.scriptInline),
            ("script-src", HostileHTML.scriptSrc),
            ("img-onerror", HostileHTML.imgOnerror),
            ("href-javascript", HostileHTML.aHrefJavascript),
            ("svg-onload", HostileHTML.svgOnload),
            ("style-tag", HostileHTML.styleTag),
            ("iframe", HostileHTML.iframeTag),
            ("form-action", HostileHTML.formAction),
            ("data-uri", HostileHTML.dataUri),
            ("entity-encoded", HostileHTML.encodedScript),
            ("template-injection", HostileHTML.templateInjection),
        ]

        print("\n═══════════════════════════════════════════════════════════")
        print("  Security A/B Test — Turndown vs html-to-md")
        print("═══════════════════════════════════════════════════════════")

        for payload in payloads {
            let (td, h2md) = await runBothEngines(html: payload.html)
            let tdStatus = td.succeeded ? "✓" : "✗ error"
            let h2mdStatus = h2md.succeeded ? "✓" : "✗ error"
            print("\n[\(payload.label)]")
            print("  Turndown  (\(tdStatus)): \(td.output.isEmpty ? "(empty)" : td.output.components(separatedBy: .newlines).first ?? "")")
            print("  html-to-md (\(h2mdStatus)): \(h2md.output.isEmpty ? "(empty)" : h2md.output.components(separatedBy: .newlines).first ?? "")")
        }

        print("\n═══════════════════════════════════════════════════════════\n")
    }
}
