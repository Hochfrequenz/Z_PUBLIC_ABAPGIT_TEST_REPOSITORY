*&---------------------------------------------------------------------*
*& Report Z_ABAPGIT_PULL
*&---------------------------------------------------------------------*
  REPORT z_abapgit_pull.

  PARAMETERS:
    p_repo   TYPE string LOWER CASE OBLIGATORY,
    p_user   TYPE string LOWER CASE,
    p_token  TYPE string LOWER CASE,
    p_trkorr TYPE trkorr.

  START-OF-SELECTION.
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

        lo_repo->deserialize(
          is_checks = ls_checks
          ii_log    = NEW zcl_abapgit_log( ) ).

        MESSAGE s398(00) WITH 'Pull successful:' lo_repo->get_name( ) '' ''.

      CATCH cx_root INTO DATA(lx_error).
        MESSAGE e398(00) WITH lx_error->get_text( ) '' '' ''.
    ENDTRY.
