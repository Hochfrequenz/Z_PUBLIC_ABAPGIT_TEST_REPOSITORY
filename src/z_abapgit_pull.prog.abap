*&---------------------------------------------------------------------*
*& Report Z_ABAPGIT_PULL
*&---------------------------------------------------------------------*
  REPORT z_abapgit_pull LINE-SIZE 1023.

* Selection screen with readable labels and F4 help
  SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
    PARAMETERS:
      p_action TYPE c LENGTH 4 DEFAULT 'PULL'.  " Action: PULL = pull repo, LIST = list all repos
    SELECTION-SCREEN COMMENT /1(60) gc_hint.     " Shows valid P_ACTION values
    PARAMETERS:
      p_repo   TYPE string LOWER CASE,           " Repository name (required for PULL)
      p_trkorr TYPE trkorr.                       " Transport request (F4 available)
  SELECTION-SCREEN END OF BLOCK b1.

  SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
    PARAMETERS:
      p_user   TYPE string LOWER CASE,             " GitHub username
      p_token  TYPE string LOWER CASE.              " GitHub PAT (Personal Access Token)
  SELECTION-SCREEN END OF BLOCK b2.

  INITIALIZATION.
    gc_hint = 'Valid actions: PULL (pull repo) | LIST (list all repos)'.

  AT SELECTION-SCREEN.
    IF p_action <> 'PULL' AND p_action <> 'LIST'.
      MESSAGE e398(00) WITH 'Invalid P_ACTION:' p_action '. Use PULL or LIST.' ''.
    ENDIF.

  START-OF-SELECTION.

* --- LIST mode: output all registered repos as tilde-delimited lines ---
    IF p_action = 'LIST'.
      TRY.
          LOOP AT zcl_abapgit_repo_srv=>get_instance( )->list( ) INTO DATA(li_repo_list).
            DATA(lv_offline) = li_repo_list->is_offline( ).
            DATA(lv_offline_flag) = COND string( WHEN lv_offline = abap_true THEN 'X' ELSE '' ).
            DATA(lv_url) = COND string( WHEN lv_offline = abap_false
                                        THEN CAST zcl_abapgit_repo_online( li_repo_list )->get_url( )
                                        ELSE '' ).
            DATA(lv_ts) = COND string( WHEN li_repo_list->ms_data-deserialized_at IS NOT INITIAL
                                       THEN |{ li_repo_list->ms_data-deserialized_at }|
                                       ELSE '' ).
            DATA(lv_line) = li_repo_list->get_name( ) && '~' &&
                            lv_url && '~' &&
                            li_repo_list->get_package( ) && '~' &&
                            li_repo_list->ms_data-branch_name && '~' &&
                            lv_ts && '~' &&
                            li_repo_list->ms_data-deserialized_by && '~' &&
                            lv_offline_flag.
            WRITE: / lv_line.
          ENDLOOP.
        CATCH cx_root INTO DATA(lx_list_error).
          MESSAGE e398(00) WITH lx_list_error->get_text( ) '' '' ''.
      ENDTRY.
      RETURN.
    ENDIF.

* --- PULL mode (existing logic, unchanged) ---
    IF p_repo IS INITIAL.
      MESSAGE e398(00) WITH 'P_REPO is required for PULL action' '' '' ''.
      RETURN.
    ENDIF.

    TRY.
        DATA lo_repo TYPE REF TO zcl_abapgit_repo_online.

        LOOP AT zcl_abapgit_repo_srv=>get_instance( )->list( iv_offline = abap_false ) INTO DATA(li_repo).
          IF li_repo->get_name( ) CS p_repo.
            lo_repo ?= li_repo.
            EXIT.
          ENDIF.
        ENDLOOP.

        IF lo_repo IS NOT BOUND.
          MESSAGE e398(00) WITH 'Repository not found:' p_repo '' ''.
          RETURN.
        ENDIF.

        IF p_user IS NOT INITIAL AND p_token IS NOT INITIAL.
          zcl_abapgit_login_manager=>set(
            iv_uri      = lo_repo->get_url( )
            iv_username = p_user
            iv_password = p_token ).
        ENDIF.

        DATA(ls_checks) = lo_repo->deserialize_checks( ).

        IF ls_checks-transport-required = abap_true AND p_trkorr IS INITIAL.
          MESSAGE e398(00) WITH 'Transport required. Provide P_TRKORR=' ls_checks-transport-type '' ''.
          RETURN.
        ENDIF.

        " Verify user has a modifiable task in the transport before deserialize.
        " Without this, deserialize silently succeeds but writes nothing.
        IF p_trkorr IS NOT INITIAL.
          SELECT SINGLE @abap_true FROM e070
            INTO @DATA(lv_task_exists)
            WHERE strkorr  = @p_trkorr
              AND as4user  = @sy-uname
              AND trstatus = 'D'.               " D = modifiable
          IF sy-subrc <> 0.
            MESSAGE e398(00) WITH 'User' sy-uname 'has no modifiable task in' p_trkorr.
            RETURN.
          ENDIF.
        ENDIF.

        ls_checks-transport-transport = p_trkorr.

        " Auto-confirm all overwrite decisions (MCP automation requires non-interactive mode)
        " Decision values: ' ' = undecided, 'Y' = overwrite, 'N' = skip
        LOOP AT ls_checks-overwrite ASSIGNING FIELD-SYMBOL(<ls_overwrite>).
          <ls_overwrite>-decision = 'Y'.
        ENDLOOP.

        DATA lo_log TYPE REF TO zif_abapgit_log.
        lo_log = NEW zcl_abapgit_log( ).

        lo_repo->deserialize(
          is_checks = ls_checks
          ii_log    = lo_log ).

        " Check the deserialization log for errors/warnings.
        " See: https://github.com/abapGit/abapGit/issues/2495
        "      https://github.com/abapGit/abapGit/issues/2821
        DATA(lv_log_status) = lo_log->get_status( ).
        IF lv_log_status = zif_abapgit_log=>c_status-error
           OR lv_log_status = zif_abapgit_log=>c_status-warning.
          DATA(lt_msgs) = lo_log->get_messages( ).
          IF lines( lt_msgs ) > 0.
            DATA(lv_msg) = lt_msgs[ 1 ]-text.
            MESSAGE e398(00) WITH 'Pull log:' lv_msg(50) lv_msg+50(50) ''.
          ELSE.
            MESSAGE e398(00) WITH 'Pull failed: deserialization log has issues' '' '' ''.
          ENDIF.
          RETURN.
        ENDIF.

        MESSAGE s398(00) WITH 'Pull successful:' lo_repo->get_name( ) '' ''.

      CATCH cx_root INTO DATA(lx_error).
        MESSAGE e398(00) WITH lx_error->get_text( ) '' '' ''.
    ENDTRY.
