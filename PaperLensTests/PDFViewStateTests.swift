//
//  PDFViewStateTests.swift
//  PaperLensTests
//
//  Exercises the PDF View State seam through PDFManager's interface: the zoom/fit
//  commands that set desired state, the ingest reducers that fold view events back,
//  and the projector's relative-tolerance scale comparison. None of these needs a
//  live window or PDFView — the interface is the test surface.
//

import AppKit
import CoreGraphics
import PDFKit
import SwiftUI
import Testing
@testable import PaperLens

@MainActor
struct PDFViewStateTests {

    // MARK: - scalesDiffer (the projector's relative-tolerance comparison)

    @Test
    func scalesDifferIgnoresSubHalfPercentChange() {
        #expect(PDFViewWrapper.scalesDiffer(1.0, 1.0) == false)
        #expect(PDFViewWrapper.scalesDiffer(1.004, 1.0) == false)   // 0.4% — PDFKit re-rounding
    }

    @Test
    func scalesDifferDetectsMeaningfulChange() {
        #expect(PDFViewWrapper.scalesDiffer(1.10, 1.0))             // 10%
        #expect(PDFViewWrapper.scalesDiffer(2.02, 2.0))            // 1%
    }

    // MARK: - Zoom commands set desired state (source of truth)

    @Test
    func zoomInStepsClampsAndClearsAutoScaleAndFit() {
        let manager = PDFManager()
        manager.scaleFactor = 1.0
        manager.isAutoScaling = true
        manager.pendingFit = FitRequest(scrollToTop: true)

        manager.zoomIn()

        #expect(manager.scaleFactor == 1.0 + DesignTokens.pdfZoomStep)
        #expect(manager.isAutoScaling == false)
        #expect(manager.pendingFit == nil)
    }

    @Test
    func zoomInClampsToMaxAndZoomOutToMin() {
        let manager = PDFManager()
        manager.scaleFactor = DesignTokens.pdfMaxScale
        manager.zoomIn()
        #expect(manager.scaleFactor == DesignTokens.pdfMaxScale)

        manager.scaleFactor = DesignTokens.pdfMinScale
        manager.zoomOut()
        #expect(manager.scaleFactor == DesignTokens.pdfMinScale)
    }

    @Test
    func setZoomClampsBothEndsAndClearsAutoScaleAndFit() {
        let manager = PDFManager()
        manager.isAutoScaling = true
        manager.pendingFit = FitRequest(scrollToTop: false)

        manager.setZoom(99)
        #expect(manager.scaleFactor == DesignTokens.pdfMaxScale)
        #expect(manager.isAutoScaling == false)
        #expect(manager.pendingFit == nil)

        manager.setZoom(-5)
        #expect(manager.scaleFactor == DesignTokens.pdfMinScale)
    }

    @Test
    func fitPageRequestsWholePageAndDisablesAutoScale() {
        let manager = PDFManager()
        manager.isAutoScaling = true
        manager.pendingFit = FitRequest(scrollToTop: true)
        manager.requestFitOnce(mode: .page)
        #expect(manager.pendingFit == FitRequest(scrollToTop: false, mode: .page))
        #expect(!manager.isAutoScaling)
    }

    @Test func fitPageCentersNarrowPageInWideViewport() async throws {
        let view = StablePDFView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.orderOut(nil) }
        let document = PDFDocument()
        for index in 0..<3 {
            let page = try #require(PDFPage(image: NSImage(size: NSSize(width: 400, height: 500), flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                return true
            }))
            document.insert(page, at: index)
        }
        view.displayMode = .singlePageContinuous
        view.autoScales = false
        view.document = document
        view.scaleFactor = 1.0
        view.layoutDocumentView()
        try await Task.sleep(for: .milliseconds(200))
        let page = try #require(document.page(at: 1))
        PDFViewWrapper.centerPage(page, in: view)
        let rect = view.convert(page.bounds(for: view.displayBox), from: page)
        #expect(abs(rect.midX - view.bounds.midX) < 2)
        #expect(abs(rect.midY - view.bounds.midY) < 2)
        let scrollView = try #require(view.documentScrollView)
        #expect(scrollView.contentView.bounds.minX < 0)
    }

    @Test(arguments: [PDFDisplayMode.twoUp, .twoUpContinuous], [0, 2, 4])
    func fitsCenterTheEntireSpreadOnFirstApplication(mode: PDFDisplayMode, pageIndex: Int) async throws {
        let view = StablePDFView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        let document = makeDocument(pageCount: 5, size: NSSize(width: 400, height: 500))
        document.page(at: 3)?.rotation = 90
        document.page(at: 3)?.setBounds(NSRect(x: 0, y: 0, width: 450, height: 650), for: .mediaBox)
        view.displayMode = mode
        view.autoScales = false
        view.document = document
        let page = try #require(document.page(at: pageIndex))
        view.go(to: page)
        view.layoutDocumentView()
        try await Task.sleep(for: .milliseconds(100))
        let manager = PDFManager()
        manager.document = document
        manager.currentPage = page
        manager.currentPageIndex = pageIndex
        manager.displayMode = mode
        let coordinator = PDFViewWrapper.Coordinator(pdfManager: manager, annotationManager: AnnotationManager(), commentManager: CommentManager(), isActive: true)
        NotificationCenter.default.addObserver(coordinator, selector: #selector(PDFViewWrapper.Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        NotificationCenter.default.addObserver(coordinator, selector: #selector(PDFViewWrapper.Coordinator.scaleChanged(_:)), name: .PDFViewScaleChanged, object: view)
        defer { NotificationCenter.default.removeObserver(coordinator) }
        view.displayMode = .singlePageContinuous
        manager.currentPage = page
        manager.currentPageIndex = pageIndex
        coordinator.project(view, documentDidChange: false)
        try await Task.sleep(for: .milliseconds(400))
        let initialSpread = PDFViewWrapper.fittedSpreadRect(page, in: view)
        #expect(abs(initialSpread.midX - view.bounds.midX) < 2, "mode \(mode.rawValue), page \(pageIndex), live page \(document.index(for: view.currentPage ?? page)) must fit without a second click")
        #expect(initialSpread.width <= view.bounds.width + 2)
        for fit in [FitEngine.Mode.page, .width] {
            view.navigateToReadingDestination(PDFDestination(page: page, at: CGPoint(x: 30, y: 100)), outlineItemID: "fit-page")
            let navigatedSpread = PDFViewWrapper.fittedSpreadRect(page, in: view)
            if navigatedSpread.width <= view.bounds.width {
                #expect(abs(navigatedSpread.midX - view.bounds.midX) < 2)
            }
            if let clip = view.documentScrollView?.contentView {
                clip.scroll(to: NSPoint(x: -200, y: clip.bounds.minY))
            }
            manager.requestFitOnce(mode: fit)
            coordinator.project(view, documentDidChange: false)
            try await Task.sleep(for: .milliseconds(400))
            let rect = PDFViewWrapper.fittedSpreadRect(page, in: view)
            #expect(abs(rect.midX - view.bounds.midX) < 2, "the spread must center after one fit")
            #expect(rect.width <= view.bounds.width + 2)
            if fit == .page { #expect(rect.height <= view.bounds.height + 2) }
            #expect(manager.pendingFit == nil)
        }
    }

    @Test(arguments: [PDFDisplayMode.twoUp, .twoUpContinuous])
    func documentRestoreKeepsSavedZoomWhenReusingView(mode: PDFDisplayMode) async throws {
        let view = StablePDFView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        let document = makeDocument(pageCount: 4, size: NSSize(width: 400, height: 500))
        view.document = document
        view.displayMode = .singlePageContinuous
        let manager = PDFManager()
        manager.document = document
        manager.currentPage = document.page(at: 2)
        manager.currentPageIndex = 2
        manager.displayMode = mode
        manager.isAutoScaling = false
        manager.scaleFactor = 1.65
        manager.pendingFit = nil
        manager.pendingScrollRestore = PDFDestination(page: document.page(at: 2)!, at: CGPoint(x: 12, y: 145))
        let coordinator = PDFViewWrapper.Coordinator(pdfManager: manager, annotationManager: AnnotationManager(), commentManager: CommentManager(), isActive: true)
        coordinator.project(view, documentDidChange: true)
        try await Task.sleep(for: .milliseconds(450))
        #expect(view.displayMode == mode)
        #expect(abs(view.scaleFactor - 1.65) < 0.01)
        #expect(manager.pendingFit == nil)
    }

    @Test(arguments: [PDFDisplayMode.singlePageContinuous, .twoUp, .twoUpContinuous])
    func samePageOutlineClicksSelectRequestedSubsectionOnce(mode: PDFDisplayMode) async throws {
        let view = StablePDFView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        let document = makeDocument(pageCount: 4, size: NSSize(width: 400, height: 900))
        let root = PDFOutline()
        let page = document.page(at: 1)!
        for (index, y) in [CGFloat(800), 450, 150].enumerated() {
            let entry = PDFOutline()
            entry.label = "Subsection \(index)"
            entry.destination = PDFDestination(page: page, at: CGPoint(x: 30, y: y))
            root.insertChild(entry, at: index)
        }
        document.outlineRoot = root
        let items = OutlineItem.buildRoot(from: root)
        view.document = document
        view.displayMode = mode
        view.autoScales = false
        view.scaleFactor = 0.55 // Entire spread fits: PDFKit cannot align every heading at the top.
        let manager = PDFManager()
        manager.document = document
        manager.displayMode = mode
        manager.currentPage = page
        manager.currentPageIndex = 1
        manager.scaleFactor = 0.55
        let coordinator = PDFViewWrapper.Coordinator(pdfManager: manager, annotationManager: AnnotationManager(), commentManager: CommentManager(), isActive: true)
        NotificationCenter.default.addObserver(coordinator, selector: #selector(PDFViewWrapper.Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        defer { NotificationCenter.default.removeObserver(coordinator) }
        for index in [2, 0, 1] {
            let previousViewport = view.documentScrollView?.contentView.bounds
            manager.goToDestination(items[index].destination!, outlineItemID: items[index].id)
            coordinator.project(view, documentDidChange: false)
            try await Task.sleep(for: .milliseconds(350))
            #expect(view.activeOutlineItemID(in: items) == items[index].id)
            if index != 2 { #expect(view.documentScrollView?.contentView.bounds == previousViewport) }
            #expect(abs(view.scaleFactor - 0.55) < 0.01)
            #expect(manager.pendingNavigation == nil)
            #expect(manager.currentPageIndex == 1)
            let settledViewport = view.documentScrollView?.contentView.bounds
            coordinator.project(view, documentDidChange: false)
            #expect(view.documentScrollView?.contentView.bounds == settledViewport)
        }
        if mode == .twoUpContinuous, let scroll = view.documentScrollView {
            scroll.contentView.scroll(to: CGPoint(x: scroll.contentView.bounds.minX, y: scroll.contentView.bounds.minY + 1000))
            scroll.reflectScrolledClipView(scroll.contentView)
            #expect(view.activeOutlineItemID(in: items) != items[1].id)
        }
    }

    @Test(arguments: [PDFDisplayMode.singlePage, .singlePageContinuous, .twoUp, .twoUpContinuous])
    func outlineClickKeepsExactParentAndCurrentPagePosition(mode: PDFDisplayMode) async throws {
        let view = StablePDFView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        let document = makeDocument(pageCount: 4, size: NSSize(width: 400, height: 900))
        let root = PDFOutline()
        let parent = PDFOutline()
        parent.label = "Section"
        let child = PDFOutline()
        child.label = "Subsection"
        let page = document.page(at: 0)!
        parent.destination = PDFDestination(page: page, at: CGPoint(x: kPDFDestinationUnspecifiedValue, y: kPDFDestinationUnspecifiedValue))
        child.destination = PDFDestination(page: page, at: CGPoint(x: 30, y: 300))
        parent.insertChild(child, at: 0)
        root.insertChild(parent, at: 0)
        document.outlineRoot = root
        let items = OutlineItem.buildRoot(from: root)
        view.document = document
        view.displayMode = mode
        view.autoScales = false
        view.scaleFactor = 1.2
        view.layoutDocumentView()
        try await Task.sleep(for: .milliseconds(100))
        view.go(to: PDFDestination(page: page, at: CGPoint(x: 30, y: 450)))
        let viewport = view.documentScrollView?.contentView.bounds
        view.navigateToReadingDestination(parent.destination!, outlineItemID: items[0].id)
        #expect(view.activeOutlineItemID(in: items) == items[0].id)
        #expect(view.documentScrollView?.contentView.bounds == viewport)
        view.navigateToReadingDestination(child.destination!, outlineItemID: items[0].children![0].id)
        #expect(view.activeOutlineItemID(in: items) == items[0].children![0].id)
        #expect(view.documentScrollView?.contentView.bounds == viewport)
        #expect(abs(view.scaleFactor - 1.2) < 0.01)
        let otherPage = document.page(at: 3)!
        view.navigateToReadingDestination(PDFDestination(page: otherPage, at: CGPoint(x: 30, y: 200)), outlineItemID: "other-page")
        try await Task.sleep(for: .milliseconds(150))
        #expect(view.visiblePages.contains { $0 === otherPage })
        #expect(view.activeOutlineItemID(in: items) == "other-page")
        #expect(view.documentScrollView?.contentInsets.top == 0)
    }

    @Test(arguments: [PDFDisplayMode.twoUp, .twoUpContinuous])
    func automaticOutlineTrackingStartsWithLeftPageOfSpread(mode: PDFDisplayMode) async throws {
        let view = StablePDFView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        let document = makeDocument(pageCount: 4, size: NSSize(width: 400, height: 900))
        let root = PDFOutline()
        for index in 0..<4 {
            let entry = PDFOutline()
            entry.label = "Page \(index)"
            entry.destination = PDFDestination(page: document.page(at: index)!, at: CGPoint(x: 30, y: 900))
            root.insertChild(entry, at: index)
        }
        let items = OutlineItem.buildRoot(from: root)
        view.document = document
        view.displayMode = mode
        view.autoScales = false
        view.scaleFactor = 1
        view.go(to: document.page(at: 2)!)
        view.layoutDocumentView()
        try await Task.sleep(for: .milliseconds(150))
        #expect(view.activeOutlineItemID(in: items) == items[2].id)
    }

    // MARK: - Fit requests

    @Test
    func requestFitOnceArmsTransientFitWithoutScrollToTop() {
        let manager = PDFManager()
        manager.isAutoScaling = true
        manager.requestFitOnce()
        #expect(manager.pendingFit == FitRequest(scrollToTop: false))
        #expect(manager.isAutoScaling == false)
    }

    @Test
    func toggleAutoScaleFlipsModeAndClearsFit() {
        let manager = PDFManager()
        manager.pendingFit = FitRequest(scrollToTop: true)
        #expect(manager.isAutoScaling == false)

        manager.toggleAutoScale()
        #expect(manager.isAutoScaling == true)
        #expect(manager.pendingFit == nil)

        manager.toggleAutoScale()
        #expect(manager.isAutoScaling == false)
    }

    // MARK: - Ingest (view event -> manager); no-op when already matching

    @Test
    func ingestScaleChangeUpdatesOnlyWhenDifferent() {
        let manager = PDFManager()
        manager.scaleFactor = 1.0

        manager.ingestScaleChange(1.0)
        #expect(manager.scaleFactor == 1.0)

        manager.ingestScaleChange(2.0)
        #expect(manager.scaleFactor == 2.0)
    }

    @Test
    func ingestDisplayModeChangeAdoptsViewMode() {
        let manager = PDFManager()
        manager.displayMode = .singlePageContinuous
        manager.ingestDisplayModeChange(.twoUp)
        #expect(manager.displayMode == .twoUp)
    }

    @Test
    func ingestPageChangeUpdatesIndexAndPage() throws {
        let document = makeDocument(pageCount: 3)
        let manager = PDFManager()
        manager.document = document
        manager.currentPageIndex = 0
        manager.currentPage = document.page(at: 0)

        let target = try #require(document.page(at: 2))
        manager.ingestPageChange(index: 2, page: target)

        #expect(manager.currentPageIndex == 2)
        #expect(manager.currentPage === target)
    }

    // MARK: - Document load arms a scroll-to-top fit

    @Test
    func finalizeDocumentLoadArmsScrollToTopFit() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let url = tempDirectory.appendingPathComponent("doc.pdf")
        #expect(makeDocument(pageCount: 2).write(to: url))

        let manager = PDFManager()
        let result = manager.loadDocument(from: url)

        guard case .success = result else {
            Issue.record("Expected the document to load successfully.")
            return
        }
        #expect(manager.pendingFit == FitRequest(scrollToTop: true))
        #expect(manager.scaleFactor == DesignTokens.pdfDefaultScale)
        #expect(manager.isAutoScaling == false)
    }

    // MARK: - Helpers

    private func makeDocument(pageCount: Int, size: NSSize = NSSize(width: 32, height: 32)) -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<pageCount {
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
            image.unlockFocus()
            guard let page = PDFPage(image: image) else {
                fatalError("Failed to create PDF page from test image.")
            }
            document.insert(page, at: index)
        }
        return document
    }
}
