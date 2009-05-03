;;; -*- Mode: LISP; Syntax: Common-Lisp; Package: ALPHA-AXP-INTERNALS; Base: 10; Lowercase: T -*-

(in-package "ALPHA-AXP-INTERNALS")

;; This ensures there are two arguments
(defmacro verify-generic-arity (cr nargs temp4)
  (let ((recheck (gensym)))
    `((load-constant ,temp4 #.1_17 "cr.apply")
      (AND ,temp4 ,cr ,temp4)
      (BEQ ,temp4 ,recheck "not applying")
      (SUBQ zero ,nargs arg1 "4 - argsize")
      ;; Pulls arg1 args and retries
      (BR zero |PullApplyArgs|)
    (label ,recheck)
      (illegal-operand too-few-arguments))))

;; Reads the instance itag/idata and returns mask data and mapping table data
(defmacro instance-descriptor-info (itag idata mask-data table-data
				    vma tag data temp temp2 temp3 temp4)
  (let ((masknotfix (gensym))
	(notlocative (gensym))
	(instance-tag (gensym))
	(non-instance-tag (gensym)))
    (push
      `((label ,non-instance-tag)
	(comment "not an instance, flavor description comes from magic vector")
	  (LDQ ,vma PROCESSORSTATE_TRAPVECBASE (ivory))
	  (TagType ,itag ,temp)
	  (LDA ,vma #.sys:%generic-dispatch-vector (,vma))
	  (ADDQ ,temp ,vma ,vma)
	  ;; We know the m-m-r is active when we are called
	  (using-multiple-memory-reads
	    (,*memoized-vmdata* ,*memoized-vmtags* ,*memoized-base* ,*memoized-limit*)
	    (memory-read ,vma ,tag ,data PROCESSORSTATE_DATAREAD ,temp ,temp2 ,temp3 ,temp4
			 ,instance-tag))
	(label ,masknotfix)
  	  (illegal-operand (flavor-search-mask-not-fixnum data-read) ,vma)
	(label ,notlocative)
	  (illegal-operand (flavor-search-table-pointer-not-locative data-read) ,vma))
      *function-epilogue*)
    `((CheckAdjacentDataTypes ,itag |TypeInstance| 4 ,non-instance-tag ,temp)
      (BIS ,idata zero ,vma "Don't clobber instance if it's forwarded")
      (memory-read ,vma ,tag ,data PROCESSORSTATE_HEADER ,temp ,temp2 ,temp3 ,temp4)
      (label ,instance-tag)
      (BIS ,data zero ,vma)
      (memory-read ,vma ,tag ,data PROCESSORSTATE_DATAREAD ,temp ,temp2 ,temp3 ,temp4)
      (BIS ,data zero ,mask-data)
      (CheckDataType ,tag |TypeFixnum| ,masknotfix ,temp)
      (ADDQ ,vma 1 ,vma)
      (memory-read ,vma ,tag ,data PROCESSORSTATE_DATAREAD ,temp ,temp2 ,temp3 ,temp4)
      (BIS ,data zero ,table-data)
      (CheckDataType ,tag |TypeLocative| ,notlocative ,temp))))

(defmacro non-instance-descriptor-info (itag idata mask-data table-data
					temp temp2 temp3 temp4 temp5 temp6 temp7
					instance-tag non-instance-tag)
  (declare (ignore idata table-data temp7 non-instance-tag))
  `((comment "not an instance, flavor description comes from magic vector")
    (LDQ ,temp5 PROCESSORSTATE_TRAPVECBASE (ivory))
    (TagType ,itag ,mask-data)
    (load-constant ,temp6 #.sys:%generic-dispatch-vector "Damned 8-bit literals!")
    (ADDQ ,mask-data ,temp5 ,mask-data)
    (ADDQ ,mask-data ,temp6 ,mask-data)
    (memory-read ,mask-data ,temp5 ,temp6 PROCESSORSTATE_DATAREAD ,temp ,temp2 ,temp3 ,temp4
		 ,instance-tag)
    ;; (BR zero ,instance) done by MEMORY-READ
    ))

;; Returns parameter ptag/pdata and method mtag/mdata
(defmacro lookup-handler (gtag gdata table mask ptag pdata mtag mdata
			  offset vma tag data temp2 temp3 temp4 temp5)
  (let ((found (gensym))
	(loop (gensym))
	)
    `((AND ,mask ,gdata ,vma)
      (SLL ,vma 1 ,temp2)
      (ADDQ ,vma ,temp2 ,offset "(* (logand mask data) 3)")
      (TagType ,gtag ,gtag)
    (label ,loop)
      (ADDQ ,table ,offset ,vma)
      (ADDQ ,offset 3 ,offset)
      (comment "Read key")
      (memory-read ,vma ,tag ,data PROCESSORSTATE_DATAREAD ,temp2 ,temp3 ,temp4 ,temp5 nil t)
      (TagType ,tag ,tag)
      (CMPEQ ,tag |TypeNIL| ,temp2)
      (branch-true ,temp2 ,found)
      (CMPEQ ,gtag ,tag ,temp2)
      (branch-false ,temp2 ,loop)
      (SUBL ,gdata ,data ,temp2)
      (branch-true ,temp2 ,loop)
    (label ,found)
      (comment "Read method")
      (addq ,vma 1 ,vma)
      (memory-read ,vma ,tag ,data PROCESSORSTATE_DATAREAD ,temp2 ,temp3 ,temp4 ,temp5)
      (BIS ,tag zero ,mtag)
      (BIS ,data zero ,mdata)
      (comment "Read parameter")
      (addq ,vma 1 ,vma)
      (memory-read ,vma ,tag ,data PROCESSORSTATE_DATAREAD ,temp2 ,temp3 ,temp4 ,temp5)
      (BIS ,tag zero ,ptag)
      (BIS ,data zero ,pdata)
      )))

(defmacro generic-dispatch (gtag gdata itag idata mtag mdata ptag pdata cr nargs temp2 temp3)
  (let ((isnil (gensym))
	(notpc (gensym)))
    `((get-control-register ,cr)
      (stack-read2-disp-signed iFP ,(* 2 8) ,gtag ,gdata "get generic tag and data")
      (AND ,cr #xFF ,nargs "get number of arguments")
      (stack-read2-disp-signed iFP ,(* 3 8) ,itag ,idata "get instance tag and data")
      (SUBQ ,nargs 4 ,nargs "done if 2 or more arguments (plus 2 extra words)")
      (BLT ,nargs |VerifyGenericArity|)		;CR in ARG6, restarts instruction
      (EXTLL ,gdata 0 ,gdata)
      (EXTLL ,idata 0 ,idata)
      (BSR R0 |LookupHandler|)			;clobbers T1-T5, T10
      (CheckAdjacentDataTypes ,mtag |TypeEvenPC| 2 ,notpc ,temp2)
      (AND ,ptag #x3F ,temp2 "Strip CDR code")
      (SUBQ ,temp2 |TypeNIL| ,temp2)
      (BEQ ,temp2 ,isnil)
      (stack-write2-disp iFP ,(* 2 8) ,ptag ,pdata)
    (label ,isnil)
      (convert-continuation-to-pc ,mtag ,mdata iPC ,temp2)
      (BR zero interpretInstructionForJump)
    (label ,notpc)
      (SCAtoVMA iSP ,temp2 ,temp3)
      (illegal-operand (generic-search-table-entry-not-pc data-read) ,temp2))))

(defmacro message-dispatch (gtag gdata itag idata mtag mdata ptag pdata cr nargs temp2 temp3)
  (let ((isnil (gensym))
	(isntnil (gensym))
	(notpc (gensym)))
    `((get-control-register ,cr)
      (stack-read2-disp-signed iFP ,(* 3 8) ,gtag ,gdata "get message tag and data")
      (AND ,cr #xFF ,nargs "get number of arguments")
      (stack-read2-disp-signed iFP ,(* 2 8) ,itag ,idata "get instance tag and data")
      (SUBQ ,nargs 4 ,nargs "done if 2 or more arguments (plus 2 extra words)")
      (BLT ,nargs |VerifyGenericArity|)		;CR in ARG6, restarts instruction
      (EXTLL ,gdata 0 ,gdata)
      (EXTLL ,idata 0 ,idata)
      (BSR R0 |LookupHandler|)			;clobbers T1-T5, T10
      (stack-read-disp iFP ,(* 2 8) ,idata "clobbered by |LookupHandler|")
      (CheckAdjacentDataTypes ,mtag |TypeEvenPC| 2 ,notpc ,temp2)
      (AND ,ptag #x3F ,temp2 "Strip CDR code")
      (SUBQ ,temp2 |TypeNIL| ,temp2)
      (BEQ ,temp2 ,isnil)
      (stack-write2-disp iFP ,(* 2 8) ,ptag ,pdata)
      (BR zero ,isntnil)
    (label ,isnil)
      (stack-write2-disp iFP ,(* 2 8) ,gtag ,gdata "swap message/instance in the frame")
    (label ,isntnil)
      (stack-write-disp iFP ,(* 3 8) ,idata)
      (convert-continuation-to-pc ,mtag ,mdata iPC ,temp2)
      (BR zero interpretInstructionForJump)
    (label ,notpc)
      (SCAtoVMA iSP ,temp2 ,temp3)
      (illegal-operand (generic-search-table-entry-not-pc data-read) ,temp2))))