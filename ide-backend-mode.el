;;; ide-backend-mode.el --- A minor mode enabling various features
;;; based on ide-backend.

;; Copyright (c) 2015 Chris Done.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Imports

(require 'haskell-cabal)
(require 'cl-lib)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Modes

(define-minor-mode ide-backend-mode
  "A minor mode enabling various features based on ide-backend."
  :lighter " IDE"
  :keymap (let ((map (make-sparse-keymap)))
            map))

(define-derived-mode inferior-ide-backend-mode javascript-mode "Inferior-IDE"
  "Major mode for interacting with an inferior ide-backend-client
process.")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Customization

(defgroup ide-backend-mode nil
  "IDE backend support for Haskell."
  :group 'haskell)

(defcustom ide-backend-mode-proc-path
  "ide-backend-client"
  "Path to the ide-backend-client executable."
  :type 'string
  :group 'ide-backend-mode)

(defcustom ide-backend-mode-paths
  ""
  "Paths made available when running the backend."
  :type 'string
  :group 'ide-backend-mode)

(defcustom ide-backend-mode-package-db
  nil
  "Path to package database. This will be configured properly by
the minor mode when it is started, but can be overriden."
  :type 'string
  :group 'ide-backend-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Interactive functions

(defun ide-backend-mode-start ()
  "Start an inferior process and buffer."
  (interactive)
  (with-current-buffer (ide-backend-mode-buffer)
    (setq buffer-read-only t)
    (cl-assert (not (comint-check-proc (current-buffer))) nil
               "This buffer (%s) already has a running process."
               (buffer-name (current-buffer)))
    (cl-assert ide-backend-mode-package-db nil
               "The package database has not been set!")
    (cd (ide-backend-mode-dir))
    (let ((process (start-process (ide-backend-mode-process-name)
                                  (ide-backend-mode-buffer)
                                  ide-backend-mode-proc-path
                                  "--path" ide-backend-mode-paths
                                  "--package-db" ide-backend-mode-package-db
                                  "empty"))))
    (inferior-ide-backend-mode)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Command queue

(defvar ide-backend-mode-queue nil
  "Command queue.")
(make-variable-buffer-local 'ide-backend-mode-queue)

(defun ide-backend-mode-queue ()
  "Get the command queue."
  (or ide-backend-mode-queue
      (setq ide-backend-mode-queue (tq-create (ide-backend-mode-process)))))

(defun ide-backend-mode-enqueue-string (string data cont)
  "Enqueue a raw STRING to the command queue, returning the
result to CONT."
  (let ((wait-for-others t))
    (ide-backend-mode-log string)
    (tq-enqueue (ide-backend-mode-queue)
                string
                "\n"
                (cons cont data)
                (lambda (cont-and-data reply)
                  (ide-backend-mode-log reply)
                  (funcall (car cont-and-data)
                           (cdr cont-and-data)
                           reply))
                wait-for-others)))

(defun ide-backend-mode-enqueue-cmd (cmd data cont)
  "Enqueue a CMD to be encoded to JSON, returning DATA and the
  result to CONT."
  (ide-backend-mode-enqueue-string
   (concat (json-encode cmd) "\n")
   (cons cont data)
   (lambda (cont-and-data reply)
     (funcall (car cont-and-data)
              (cdr cont-and-data)
              (json-read-from-string reply)))))

(defun ide-backend-mode-log (string)
  "Log a string to the inferior buffer."
  (with-current-buffer (ide-backend-mode-buffer)
    (goto-char (point-max))
    (let ((inhibit-read-only t))
      (insert string))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Project functions

(defun ide-backend-mode-process ()
  "Get the current process."
  (get-buffer-process (ide-backend-mode-buffer)))

(defun ide-backend-mode-buffer ()
  "The inferior buffer."
  (get-buffer-create (ide-backend-mode-buffer-name)))

(defun ide-backend-mode-process-name ()
  "Name for the inferior process."
  (format "ide-backend:%s"
          (ide-backend-mode-name)))

(defun ide-backend-mode-buffer-name ()
  "Name for the inferior buffer."
  (format "*ide-backend:%s*"
          (ide-backend-mode-name)))

(defun ide-backend-mode-dir ()
  "The directory for the project."
  (file-name-directory (haskell-cabal-find-file)))

(defun ide-backend-mode-name ()
  "The name for the current project based on the current
directory."
  (let ((file (haskell-cabal-find-file)))
    (downcase (file-name-sans-extension
               (file-name-nondirectory file)))))

(provide 'ide-backend-mode)
