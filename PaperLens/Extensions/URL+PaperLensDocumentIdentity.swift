//
//  URL+PaperLensDocumentIdentity.swift
//  PaperLens
//
//  Canonical file URL helpers for document identity comparisons.
//

import Foundation

extension URL {
    var paperLensCanonicalDocumentURL: URL {
        guard isFileURL else { return self }
        return standardizedFileURL.resolvingSymlinksInPath()
    }
}
