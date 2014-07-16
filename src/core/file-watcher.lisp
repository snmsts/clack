(in-package :cl-user)
(defpackage clack.file-watcher
  (:use :cl)
  (:import-from :alexandria
                :compose
                :ensure-list)
  (:import-from :bordeaux-threads
                :make-thread
                :destroy-thread))
(in-package :clack.file-watcher)

(cl-syntax:use-syntax :annot)

(defvar *system-component-pathnames*
  (make-hash-table :test 'equal))

(defstruct (source-file (:constructor make-source-file (pathname
                                                        &aux (mtime (if (probe-file pathname)
                                                                        (file-write-date pathname)
                                                                        0)))))
  (mtime 0 :type integer)
  (pathname nil :type pathname))

(defstruct (asd-file (:include source-file (mtime) (pathname))
                     (:constructor make-asd-file (system pathname
                                                  &aux (mtime (if (probe-file pathname)
                                                                  (file-write-date pathname)
                                                                  0)))))
  (system nil :type asdf:system))

(defun system-source-files (system)
  (mapcar (compose #'make-source-file #'asdf:component-pathname)
          (remove-if-not (lambda (comp)
                           (typep comp 'asdf:source-file))
                         (asdf::sub-components system))))

(defun compute-diff (a b)
  (let ((hash (make-hash-table :test 'equal)))
    (loop for item in a
          do (incf (gethash item hash 0)))
    (loop for item in b
          do (incf (gethash item hash 0) 2))
    (loop for item being the hash-keys in hash using (hash-value val)
          when (= val 1)
            collect item into deleted
          when (= val 2)
            collect item into added
          when (= val 3)
            collect item into common
          finally
             (return (values added deleted common)))))

(defmacro with-safety-loading (file &body body)
  `(handler-case (progn (load ,file) ,@body)
     (error (e)
       (format *error-output*
               "~&Error while loading ~A:~%~A: ~A~%"
               ,file
               (type-of e)
               e))))

(defun update-system-components (system)
  (multiple-value-bind (source-files watching-p)
      (gethash (slot-value system 'asdf::source-file)
               *system-component-pathnames*)
    (let ((new-source-files (system-source-files system)))
      (unless watching-p
        (format *terminal-io*
                "~&; Starting to watch a system \"~A\".~%"
                (asdf:component-name system)))
      (loop for file in (compute-diff (mapcar #'source-file-pathname
                                              source-files)
                                      (mapcar #'source-file-pathname
                                              new-source-files))
            do (format *terminal-io*
                       "~&; new file: ~A~%" file)
            when (and watching-p (probe-file file))
              do (let ((*load-verbose* t))
                   (with-safety-loading file)))
      (setf (gethash (slot-value system 'asdf::source-file)
                     *system-component-pathnames*)
            (cons
             (make-asd-file system (slot-value system 'asdf::source-file))
             new-source-files)))))

(defgeneric on-update (file)
  (:method ((file asd-file))
    (let ((*load-verbose* nil))
      (with-safety-loading (asd-file-pathname file)
        (update-system-components (asd-file-system file)))))
  (:method ((file source-file))
    (let ((*load-verbose* t))
      (with-safety-loading (source-file-pathname file)))))

(defgeneric on-delete (file)
  (:method ((file asd-file))
    (format *terminal-io*
            "~&; Stop watching \"~A\" because it has deleted.~%"
            (asdf:component-name (asd-file-system file)))
    (remhash (asd-file-pathname file)
             *system-component-pathnames*))
  (:method ((file source-file))
    ;; Do nothing.
    ))

(defgeneric check-update (target)
  (:method ((target source-file))
    (let ((file (source-file-pathname target)))
      (cond
        ((not (probe-file file))
         (on-delete target))
        ((not (= (source-file-mtime target)
                 (file-write-date file)))
         (setf (source-file-mtime target)
               (file-write-date file))
         (on-update target)))))
  (:method ((target asdf:system))
    (map nil #'check-update
         (gethash (slot-value target 'asdf::source-file)
                  *system-component-pathnames*))))

(defvar *current-watcher* (make-hash-table :test 'eq))

@export
(defun watch-systems (identifier systems &key (use-thread t))
  (let ((systems (mapcar #'asdf:find-system (ensure-list systems)))
        (terminal-io *terminal-io*)
        (standard-output *standard-output*)
        (error-output *error-output*))
    (flet ((watch-loop ()
             (map nil #'update-system-components systems)
             (loop
               (sleep 1)
               (map nil #'check-update systems))))
      (when (gethash identifier *current-watcher*)
        (stop-watching identifier))
      (if use-thread
          (let ((thread (bt:make-thread
                         (lambda ()
                           (let ((*terminal-io* terminal-io)
                                 (*standard-output* standard-output)
                                 (*error-output* error-output))
                             (watch-loop))))))
            (setf (gethash identifier *current-watcher*) thread)
            thread)
          (watch-loop)))))

@export
(defun stop-watching (identifier)
  (when (gethash identifier *current-watcher*)
    (bt:destroy-thread (gethash identifier *current-watcher*))
    (remhash identifier *current-watcher*)
    t))
