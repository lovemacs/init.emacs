(defvar *init-status*
  ;;;;;;;;;;
  (catch 'quit
    ;; to avoid loading this file recursively
    (if (boundp '*init-time*)
        (throw 'quit "have been loaded"))
    (defalias '~ 'funcall)
    ;;;;;;;;
    (let* ((this-file (file-name-nondirectory load-file-name))
           (this-dir (file-name-directory load-file-name))
           (tmp (make-temp-name ""))
           init-name-match base-dir pre-init-files init-dir init-files
           dirs ; default
           (_check-directory
            (lambda (x &optional dir-p base)
              (let ((f (expand-file-name x (or base *init-dir*))))
                (unless (file-exists-p f)
                  (if dir-p
                      (progn (make-directory f)
                             (message (concat "New dir " f)))
                    (progn (find-file f)
                           (message (concat "New file " f))))))))
           (_load
            (lambda (lst &optional var)
              (let* ((var (or var '*init-time*))
                     tm)
                (mapc
                 (lambda (f)
                   (setq tm (float-time))
                   (load f)
                   (set var
                        (cons
                         (cons
                          (file-name-nondirectory f)
                          (- (float-time) tm))
                         (eval var))))
                 lst))))
           (_autoload
            (lambda (dir &optional var)
              (let* ((var (or var '*init-time*))
                     (d (expand-file-name dir *init-dir*))
                     (load-file-name (expand-file-name tmp d)))
                (set var
                     (cons
                      (cons
                       (format "gen autoload for %s" dir)
                       (lazily d))
                      (eval var))))))
           (_message
            (lambda(x)
              (message (concat "=======>" x)))))
      ;;;;;;
      (setq dirs
            '((lib-dir   .   "_lib/")
              (lib-df    .   "_loaddefs")
              (ext-dir   .   "_extensions_")
              (eal-dir   .   "_eval-after-load/")
              (alc-dir   .   "_autoload-conf/")
              (wk-dir    .   "sandbox/")))

      ;;
      (~ _message "Find *init-dir*")
      (cond
       ;; when specify *init-dir* outside, and load this file
       ((boundp '*init-dir*) nil)
       ;; when this file's name is /home/.../.emacs or /.../emacs/.../site-start.el
       ((member load-file-name
                (mapcar 'expand-file-name
                        (list "~/.emacs"
                              (or (locate-library site-run-file) tmp))))
        (setq
         init-name-match
         "init.*el\\|init.*emacs\\|emacs.*init"
         base-dir
         (apply 'expand-file-name
                (cond
                 ((eq system-type 'windows-nt)
                  `(".." ,exec-directory))
                 (t
                  `("~"))))
         init-dir
         ((lambda (x) (file-name-as-directory
                   ;; *init-dir* is the newest directory with "init" and "emacs" in it's name
                   ;; or directory where this file is located (*init-dir* is $HOME or site-lisp)
                   (or (car (sort x 'file-newer-than-file-p)) this-dir)))
          (mapcar (lambda (x) (if (file-directory-p x) x tmp))
                  (directory-files base-dir t init-name-match t)))))
       ;; when this file's name is not .emacs or site-start.el, for example as bootstrap.el
       ;; load this file in emacs init file : (load "...../bootstrap.el")
       (t (setq init-dir this-dir)))
      ;; export
      (defvar *init-time* nil)
      (defvar *init-dir* init-dir)
      (message (format "*init-dir* is %s" *init-dir*))
      (defvar *init-dirs*
        (mapcar
         (lambda(x)
           (cons
            (car x)
            (expand-file-name (cdr x) *init-dir*)))
         dirs))
      ;;;;;;
      (if (null (file-exists-p *init-dir*))
          (throw 'quit "can't found *init-dir*"))
      ;;;;;;
      (setq pre-init-files
            (mapcar
             (lambda (f) (file-name-sans-extension f))
             (directory-files *init-dir* t "^__.*\\.el\\'"))
            init-files
            (mapcar
             (lambda (f) (file-name-sans-extension f))
             (directory-files *init-dir* t "^[^_].*\\.el\\'")))

      ;; load pre-init-files
      (~ _message "Load pre-init-files")
      (~ _load pre-init-files)

      ;; add "_xxx_" to load-path
      (~ _message "Add load-path")
      (mapc
       (lambda (p)
         (if (file-directory-p p)
             (and
              (add-to-list 'load-path p)
              (message (format "Add %s to load-path" p)))))
       (directory-files *init-dir* t "^_.*_\\'"))
      ;; lib
      (~ _message "Load lib")
      (~ _check-directory (cdr (assoc 'lib-dir dirs)) t *init-dir*)
      (~ _autoload (cdr (assoc 'lib-dir dirs)))
      ;; autoload-conf
      (~ _message "Load autoload-conf")
      (~ _autoload (cdr (assoc 'alc-dir dirs)))
      ;; *feature-file-hash*
      (~ _message "Load eval-after-load")
      (setq tmp (float-time))
      (defvar *feature-file-hash* (make-hash-table :test 'equal :size 20))
      (let ((dir (cdr (assoc 'eal-dir dirs))))
        (~ _check-directory dir t *init-dir*)
        (mapc
         (lambda (x)
           (puthash
            (intern (file-name-sans-extension (file-name-nondirectory x))) x
            *feature-file-hash*))
         (directory-files (expand-file-name dir *init-dir*) t "\\.el\\'")))
      ;;;;;;
      (maphash
       (lambda (x y)
         (eval-after-load x `(load ,y))
         (message (format "eval-after-load %s" y)))
       *feature-file-hash*)
      (setq *init-time*
            (cons
             (cons "gen eval-after-load"
                   (- (float-time) tmp))
             *init-time*))
      ;; byte-compile
      (when nil
        (~ _message "byte-compile")
        ;; delete elc without el
        (mapc (lambda(f)(or (file-exists-p (substring f 0 -1))
                        (delete-file f)))
              (directory-files *init-dir* t "\\.elc\\'"))
        ;; recompile
        (eval-when-compile (require 'bytecomp))
        (mapc (lambda(f) (byte-recompile-file f nil 0))
              (directory-files *init-dir* t "\\.el\\'")))
      ;; load *.elc || *.el in *init-dir*
      (~ _message "Load init-files")
      (~ _load init-files)
      ;;;;;;
      (~ _message "Calc *init-time*")
      (setq *init-time*
            (cons
             (list 'init
                   (apply '+ (mapcar 'cdr *init-time*)))
             (reverse *init-time*)))
      ;; when init finished, echo some info
      (add-hook
       'emacs-startup-hook
       '(lambda ()
          (mapc
           (lambda(x) (plist-put (car *init-time*) (car x)(cdr x)))
           (list
            (cons 'emacs
                  (- (float-time after-init-time) (float-time before-init-time)))
            (cons 'other
                  (- (float-time) (float-time after-init-time)))))
          (message "load %d init file, spend %g seconds; startup spend %g seconds"
                   (- (length *init-time*) 1)
                   (plist-get (car *init-time*) 'init)
                   (+
                    (plist-get (car *init-time*) 'emacs)
                    (plist-get (car *init-time*) 'other))))))
    ;;;;;;;;
    "success"))
