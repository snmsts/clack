#|
  This file is a part of Clack package.
  URL: http://github.com/fukamachi/clack
  Copyright (c) 2011 Eitaro Fukamachi <e.arrows@gmail.com>

  Clack is freely distributable under the LLGPL License.
|#

#|
  Clack is a Web server Interface for Common Lisp.

  Author: Eitaro Fukamachi (e.arrows@gmail.com)
|#

(in-package :cl-user)
(defpackage clack-asd
  (:use :cl :asdf))
(in-package :clack-asd)

(defsystem clack
  :version "2.0.0"
  :author "Eitaro Fukamachi"
  :license "LLGPL"
  :depends-on (:lack
               :lack-util

               ;; Utility
               :alexandria
               :split-sequence
               :cl-syntax
               :cl-syntax-annot

               ;; for Other purpose
               :cl-ppcre
               :bordeaux-threads)
  :components ((:module "src"
                :components
                ((:module "core"
                  :depends-on ("util")
                  :components
                  ((:file "clack"
                    :depends-on ("handler"))
                   (:file "handler")
                   (:file "http-status")))
                 (:file "util"))))
  :description "Web application environment for Common Lisp"
  :long-description
  #.(with-open-file (stream (merge-pathnames
                             #p"README.markdown"
                             (or *load-pathname* *compile-file-pathname*))
                            :if-does-not-exist nil
                            :direction :input)
      (when stream
        (let ((seq (make-array (file-length stream)
                               :element-type 'character
                               :fill-pointer t)))
          (setf (fill-pointer seq) (read-sequence seq stream))
          seq)))
  :in-order-to ((test-op (test-op t-clack)
                         (test-op t-clack-handler-hunchentoot)
                         (test-op t-clack-handler-wookie)
                         (test-op t-clack-handler-fcgi)
                         (test-op t-clack-handler-toot)
                         (test-op t-clack-middleware-csrf)
                         (test-op t-clack-middleware-auth-basic))))
