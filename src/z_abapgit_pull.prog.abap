*&---------------------------------------------------------------------*
*& Report Z_ABAPGIT_PULL
*&---------------------------------------------------------------------*
*& PURPOSE:
*&   Pull changes from an abapGit repository using the abapGit ABAP API.
*&   Designed to be called via transaction Z_ABAPGIT_PULL for automation
*&   by MCP tools (Model Context Protocol).
*&
*& WHY THIS APPROACH:
*&   The abapGit web UI is fragile for automation (complex dialogs,
*&   custom elements, timing issues). Using the ABAP API directly is
*&   more reliable, faster, and stable across abapGit versions.
*&
*& PARAMETERS:
*&   P_REPO   - Repository name pattern (matched against registered repos)
*&   P_USER   - GitHub username (optional for public repos)
*&   P_TOKEN  - GitHub PAT token (optional for public repos)
*&   P_TRKORR - Transport request (optional, error if required but missing)
*&
*& STATUS BAR MESSAGES (read by MCP tool via sap_read_status_bar):
*&   Success: "Pull successful: <repo_name>"
*&   Error:   "Repository not found: <pattern>"
*&   Error:   "Transport required. Provide P_TRKORR=<type>"
*&   Error:   "<exception message>"
*&
*& API REFERENCE: https://docs.abapgit.org/development-guide/api/api.html
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
