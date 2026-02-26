*&---------------------------------------------------------------------*
*& Report Z_ABAPGIT_PULL
*&---------------------------------------------------------------------*
  REPORT z_abapgit_pull LINE-SIZE 1023.

* Selection screen with readable labels and F4 help
  SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
    PARAMETERS:
      p_action TYPE c LENGTH 4 DEFAULT 'PULL',  " Action: PULL or LIST
      p_repo   TYPE string LOWER CASE,           " Repository name
      p_trkorr TYPE trkorr.                       " Transport request (F4 available)
  SELECTION-SCREEN END OF BLOCK b1.

  SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
    PARAMETERS:
      p_user   TYPE string LOWER CASE,             " GitHub username
      p_token  TYPE string LOWER CASE.              " GitHub PAT (Personal Access Token)
  SELECTION-SCREEN END OF BLOCK b2.

  START-OF-SELECTION.

* --- LIST mode: output all registered repos as pipe-delimited lines ---
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
        ls_checks-transport-transport = p_trkorr.

        " Auto-confirm all overwrite decisions (MCP automation requires non-interactive mode)
        " Decision values: ' ' = undecided, 'Y' = overwrite, 'N' = skip
        LOOP AT ls_checks-overwrite ASSIGNING FIELD-SYMBOL(<ls_overwrite>).
          <ls_overwrite>-decision = 'Y'.
        ENDLOOP.

        lo_repo->deserialize(
          is_checks = ls_checks
          ii_log    = NEW zcl_abapgit_log( ) ).

        MESSAGE s398(00) WITH 'Pull successful:' lo_repo->get_name( ) '' ''.

      CATCH cx_root INTO DATA(lx_error).
        MESSAGE e398(00) WITH lx_error->get_text( ) '' '' ''.
    ENDTRY.
