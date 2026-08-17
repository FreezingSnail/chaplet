;;; probes/focus-order.el --- window-buffer-change-functions ordering probe
;; Question: when `chaplet-list-set-view' calls `switch-to-buffer', does the
;; `window-buffer-change-functions' hook fire synchronously (before the
;; explicit refresh) or later?  Determines whether the debounce alone yields
;; exactly one fetch per view switch.

(ert-deftest probe-focus-hook-timing ()
  (let ((log nil)
        (fetches 0))
    (cl-letf (((symbol-function 'chaplet-list--fetch)
               (lambda (_view) (cl-incf fetches) (push (list 'fetch fetches) log) nil))
              ((symbol-function 'chaplet-list-refresh)
               (lambda ()
                 (cl-incf fetches)
                 (push (list 'refresh fetches) log)
                 (setq tabulated-list-entries nil)
                 (tabulated-list-init-header)
                 (tabulated-list-print))))
      ;; Replace the buffer-local hook with our own tracer to observe when it runs.
      (with-current-buffer (get-buffer-create "*probe-focus*")
        (chaplet-list-mode)
        (setq-local window-buffer-change-functions
                    (list (lambda (win)
                            (push (list 'hook
                                        (buffer-name (window-buffer win))
                                        (buffer-name (current-buffer))
                                        fetches)
                                  log))))
        (setq fetches 0)
        ;; From a different buffer, switch to the list buffer (view switch path)
        (with-current-buffer (get-buffer-create "*probe-other*")
          (chaplet-list-set-view 'open)))
      (princ (format "LOG=%S\n" (nreverse log)))
      (should (= fetches 1)))))