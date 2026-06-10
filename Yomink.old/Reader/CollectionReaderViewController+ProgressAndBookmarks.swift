import UIKit

@MainActor
extension CollectionReaderViewController {
    func updateSessionState(isLoadingNextPage: Bool) {
        self.isLoadingNextPage = isLoadingNextPage
        updateCurrentProgress()
        refreshBookmarkState()
    }

    func updateCurrentProgress() {
        guard let currentPage,
              let chapter = chapter(containingAbsoluteOffset: currentPage.startAbsoluteOffset) else {
            currentProgress = nil
            return
        }

        let chapterOffset = currentPage.startAbsoluteOffset - chapter.startOffset
        let total = max(chapters.last?.endOffset ?? chapter.endOffset, 1)
        let globalProgress = min(max(Double(currentPage.startAbsoluteOffset) / Double(total), 0), 1)
        currentProgress = ReadingProgress(
            bookID: book.id,
            chapterID: chapter.id,
            chapterOffset: Int64(max(chapterOffset, 0)),
            globalProgress: globalProgress
        )
        progressLabel.text = progressText(
            chapter: chapter,
            chapterProgress: chapter.byteLength > 0 ? Double(max(chapterOffset, 0)) / Double(chapter.byteLength) : 0,
            globalProgress: globalProgress
        )
        if !isTrackingProgressSlider {
            progressSlider.value = Float(chapterProgress(for: currentPage, in: chapter))
        }
        updateFixedWidgetOverlay()
    }

    private func chapterProgress(
        for page: CollectionReaderPage,
        in chapter: Chapter
    ) -> Double {
        guard chapter.byteLength > 0 else {
            return 0
        }
        let offset = max(page.startAbsoluteOffset - chapter.startOffset, 0)
        return min(max(Double(offset) / Double(chapter.byteLength), 0), 1)
    }

    private func progressText(
        chapter: Chapter,
        chapterProgress: Double,
        globalProgress: Double
    ) -> String {
        String(
            format: NSLocalizedString("reader.progress.format", comment: ""),
            chapter.title,
            ReadingProgressFormatter.percentString(from: chapterProgress),
            ReadingProgressFormatter.percentString(from: globalProgress)
        )
    }

    private func progressTooltipText(
        chapterProgress: Double,
        pageIndex: Int
    ) -> String {
        String(
            format: NSLocalizedString("reader.progress.tooltip.format", comment: ""),
            ReadingProgressFormatter.tooltipPercentString(from: chapterProgress),
            pageIndex + 1
        )
    }

    private func updateProgressTooltip() {
        if let target = targetProgressInCurrentChapter(progress: Double(progressSlider.value)) {
            updateProgressTooltip(target: target)
        } else if let currentPage,
                  let chapter = chapter(containingAbsoluteOffset: currentPage.startAbsoluteOffset) {
            updateProgressTooltip(
                target: (
                    chapter: chapter,
                    chapterOffset: max(currentPage.startAbsoluteOffset - chapter.startOffset, 0),
                    chapterProgress: chapterProgress(for: currentPage, in: chapter),
                    pageIndex: currentPage.localPageIndex
                )
            )
        }
    }

    private func updateProgressTooltip(
        target: (chapter: Chapter, chapterOffset: Int, chapterProgress: Double, pageIndex: Int)
    ) {
        progressTooltipLabel.text = progressTooltipText(
            chapterProgress: target.chapterProgress,
            pageIndex: target.pageIndex
        )
    }

    private func setProgressTooltipVisible(_ visible: Bool) {
        if visible {
            progressTooltipView.isHidden = false
        }
        UIView.animate(
            withDuration: 0.08,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            self.progressTooltipView.alpha = visible ? 1 : 0
        } completion: { _ in
            if !visible {
                self.progressTooltipView.isHidden = true
            }
        }
    }

    func refreshBookmarkState() {
        guard let currentProgress else {
            currentBookmark = nil
            updateBookmarkButton()
            return
        }
        currentBookmark = bookmarks.first { bookmark in
            bookmark.chapterID == currentProgress.chapterID
                && abs(bookmark.offset - Int(currentProgress.chapterOffset)) < 12
        }
        updateBookmarkButton()
    }

    private func updateBookmarkButton() {
        let imageName = currentBookmark == nil ? "bookmark" : "bookmark.fill"
        bookmarkButton.setImage(UIImage(systemName: imageName), for: .normal)
        bookmarkButton.accessibilityLabel = NSLocalizedString(
            currentBookmark == nil ? "reader.bookmark.add" : "reader.bookmark.remove",
            comment: ""
        )
    }

    func scheduleProgressSave() {
        guard let progress = currentProgress else {
            return
        }
        saveGeneration += 1
        let generation = saveGeneration
        saveTask?.cancel()
        let repository = repository
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
                try Task.checkCancellation()
                guard generation == saveGeneration else {
                    return
                }
                try await repository.saveReadingProgress(progress)
                await MainActor.run { [weak self] in
                    self?.didShowProgressSaveError = false
                }
            } catch is CancellationError {
            } catch {
                readerLogger.error("Failed to save reading progress: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { [weak self] in
                    self?.showProgressSaveErrorIfNeeded(error)
                }
            }
        }
    }

    func saveProgressImmediately() {
        guard let progress = currentProgress else {
            return
        }
        saveTask?.cancel()
        let repository = repository
        saveTask = Task { [weak self] in
            do {
                try await repository.saveReadingProgress(progress)
                await MainActor.run {
                    self?.didShowProgressSaveError = false
                }
            } catch is CancellationError {
            } catch {
                readerLogger.error("Failed to save reading progress immediately: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self?.showProgressSaveErrorIfNeeded(error)
                }
            }
        }
    }

    func recordBookOpenedIfNeeded() {
        guard !didRecordOpenHistory,
              let progress = currentProgress else {
            return
        }
        didRecordOpenHistory = true
        openHistoryGeneration += 1
        let generation = openHistoryGeneration
        let repository = repository
        let bookID = book.id
        let historyDate = openedAt
        openHistoryTask?.cancel()
        openHistoryTask = Task { [weak self] in
            do {
                try await repository.saveReadingProgress(progress)
                try Task.checkCancellation()
                await MainActor.run {
                    self?.didShowProgressSaveError = false
                }
                try await repository.markBookOpened(id: bookID, at: historyDate)
            } catch is CancellationError {
            } catch {
                readerLogger.error("Failed to record reading history: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard let self,
                          self.openHistoryGeneration == generation else {
                        return
                    }
                    self.didRecordOpenHistory = false
                    self.showError(error)
                }
            }
        }
    }

    private func showProgressSaveErrorIfNeeded(_ error: Error) {
        guard !didShowProgressSaveError else {
            return
        }
        didShowProgressSaveError = true
        showError(error)
    }

    private func targetProgressInCurrentChapter(
        progress: Double
    ) -> (chapter: Chapter, chapterOffset: Int, chapterProgress: Double, pageIndex: Int)? {
        guard let currentPage,
              let chapter = chapter(containingAbsoluteOffset: currentPage.startAbsoluteOffset)
        else {
            return nil
        }

        let chapterProgress = min(max(progress, 0), 1)
        let maxOffset = max(chapter.byteLength - 1, 0)
        let chapterOffset = min(
            max(Int((Double(chapter.byteLength) * chapterProgress).rounded(.down)), 0),
            maxOffset
        )
        let estimatedPageIndex = pageIndex(
            containingChapterOffset: chapterOffset,
            in: currentPage
        )
        return (
            chapter: chapter,
            chapterOffset: chapterOffset,
            chapterProgress: chapterProgress,
            pageIndex: estimatedPageIndex
        )
    }

    private func bookmarkPreview(near absoluteOffset: Int) -> String {
        guard let page = currentPage else {
            return NSLocalizedString("reader.bookmark.preview.empty", comment: "")
        }
        return String(page.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    @objc func bookmarkButtonTapped() {
        setMoreMenuVisible(false, animated: true)
        guard let currentProgress,
              let chapter = chapter(containingAbsoluteOffset: currentDisplayByteOffset()) else {
            return
        }

        if let currentBookmark {
            let removedBookmark = currentBookmark
            let removedBookmarkIndex = bookmarks.firstIndex { $0.id == removedBookmark.id } ?? 0
            bookmarkTask?.cancel()
            self.currentBookmark = nil
            bookmarks.removeAll { $0.id == removedBookmark.id }
            bookmarkButton.isEnabled = false
            updateBookmarkButton()
            let repository = repository
            bookmarkTask = Task { [weak self] in
                do {
                    try await repository.deleteBookmark(id: removedBookmark.id)
                    await MainActor.run {
                        self?.bookmarkButton.isEnabled = true
                        self?.refreshBookmarkState()
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self?.bookmarkButton.isEnabled = true
                        self?.refreshBookmarkState()
                    }
                } catch {
                    readerLogger.error("Failed to delete bookmark: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        guard let self else {
                            return
                        }
                        self.bookmarks.removeAll { $0.id == removedBookmark.id }
                        self.bookmarks.insert(
                            removedBookmark,
                            at: min(removedBookmarkIndex, self.bookmarks.count)
                        )
                        self.bookmarkButton.isEnabled = true
                        self.refreshBookmarkState()
                        self.showError(error)
                    }
                }
            }
            return
        }

        let offset = Int(currentProgress.chapterOffset)
        let preview = bookmarkPreview(near: currentDisplayByteOffset())
        let repository = repository
        let bookID = book.id
        bookmarkButton.isEnabled = false
        bookmarkTask?.cancel()
        bookmarkTask = Task { [weak self] in
            do {
                let bookmark = try await repository.createBookmark(
                    bookID: bookID,
                    chapterID: chapter.id,
                    offset: offset,
                    preview: preview
                )
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.bookmarkButton.isEnabled = true
                    self.bookmarks.removeAll { $0.id == bookmark.id }
                    self.bookmarks.insert(bookmark, at: 0)
                    self.refreshBookmarkState()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.bookmarkButton.isEnabled = true
                }
            } catch {
                readerLogger.error("Failed to create bookmark: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.bookmarkButton.isEnabled = true
                    self.refreshBookmarkState()
                    self.showError(error)
                }
            }
        }
    }

    @objc func progressSliderTouchBegan() {
        stopAutoReading(restoreLayout: true, animated: true)
        isTrackingProgressSlider = true
    }

    @objc func progressSliderChanged() {
        guard let target = targetProgressInCurrentChapter(progress: Double(progressSlider.value)) else {
            return
        }
        let total = max(chapters.last?.endOffset ?? target.chapter.endOffset, 1)
        let absoluteOffset = target.chapter.startOffset + target.chapterOffset
        let globalProgress = min(max(Double(absoluteOffset) / Double(total), 0), 1)
        progressLabel.text = progressText(
            chapter: target.chapter,
            chapterProgress: target.chapterProgress,
            globalProgress: globalProgress
        )
        updateProgressTooltip(target: target)
        setProgressTooltipVisible(true)
    }

    @objc func progressSliderTouchFinished() {
        isTrackingProgressSlider = false
        setProgressTooltipVisible(false)
        guard let target = targetProgressInCurrentChapter(progress: Double(progressSlider.value)) else {
            return
        }
        pagingGeneration += 1
        openPage(
            absoluteOffset: target.chapter.startOffset + target.chapterOffset,
            generation: pagingGeneration,
            showsLoadingIndicator: false
        )
    }
}
