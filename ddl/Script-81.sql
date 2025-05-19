CREATE OR REPLACE PROCEDURE WMSRDC.SP_W_STK_MOVE01_P01
/******************************************************************************
* AUTHOR    : NEXEN WMS RDC Project Team 2023
* DATE      : 2023. 12. 26
* COMPANY   : NEXEN TIRE, NEXEN L
* COPYRIGHT : DMSIS    
===============================================================================
* DESCRIPTION  : P/T 전체이동
===============================================================================
* CHANGE LOG
    DATE        VERSION        DEVELOPER        COMMENTS
    --------    -------        -----------      -------------------------------
1.  20170208    1.0
2.  20230828    1.1            CSM              Compiled For WMSRDC
3.  20231227    2.0            SOO              from SP_PDA_MOVE01_P01, 다중 건수 처리
4.  20240621    2.1            SOO              RDC 조건 추가
*******************************************************************************/
(
    p_lang         IN VARCHAR2 -- language, timezone, revision
  , p_plant        IN VARCHAR2 -- plant code
  , p_rdc_code     IN VARCHAR2 -- RDC Code
  , p_user_id      IN VARCHAR2 -- User ID
  , p_user_ip      IN VARCHAR2 -- IP Address
  , p_pgm          IN VARCHAR2 -- Program Calling Proc.
  , p_proc         IN VARCHAR2 -- Procedure Called
  , p_case         IN VARCHAR2 -- 'INSERT' 'UPDATE' 'DELETE' 'SELECT'
    --------------------------------------------------------------------------
  , p_query_option IN VARCHAR2
    --------------------------------------------------------------------------
  , p_out_result  OUT VARCHAR2               -- ok / err / info
  , p_out_msg     OUT VARCHAR2                  -- 사용자에게 보여줄 메세지
  , p_out_cursor  OUT PKG_SYS_RETURN.T_CURSOR  -- 데이터
)
AS
    USER_ERROR      EXCEPTION;
    v_errType       VARCHAR2(10)   := '';
    v_errDesc       VARCHAR2(4000) := 'N/A';
    v_memo          VARCHAR2(2000) := 'SP_W_STK_MOVE01_P01'; -- Procedure 명 및 추가 메모사항 입력

    V_LOCDATE           DATE := SF_GET_LOCALE_CUR_DATE(P_PLANT, P_RDC_CODE); -- ADD 20240202 SOO

  E_FKCONSTRAINT_ERR    EXCEPTION;
  PRAGMA EXCEPTION_INIT (E_FKCONSTRAINT_ERR, -2292);
  v_outCode             VARCHAR2(10) := '';
--  v_errDesc             VARCHAR2(1000) := '';
--  v_errType             VARCHAR2(10) := '';

  v_cnt                 NUMBER(10) := 0;
--  USER_ERROR            EXCEPTION;

  v_TO_pltno            number(10);
  v_max_seq             int;
  V_YYYYMMDD            VARCHAR2(8);

--  p_plant               VARCHAR2(10);
  v_WHOUSECODE          VARCHAR2(4);
  v_ADDR                VARCHAR2(10);

  v_JOBINFO            VARCHAR2(500) := '';
  v_pROCEDURENAME      VARCHAR2(40)  := 'SP_W_STK_MOVE01_P01';
  v_JBONAME            VARCHAR(40)   := '[MOVE PLT]';

  v_MOVNO              VARCHAR(14);
  v_MOVTYPE            VARCHAR(10);
  v_RETURN             VARCHAR2(10) := '';


    IPADDRESS          VARCHAR2(1000) := '';
    PDANO              VARCHAR2(1000) := '';
    PLTNO              VARCHAR2(1000) := '';
    LOC1               VARCHAR2(1000) := '';
    LOC2               VARCHAR2(1000) := '';
    LOC3               VARCHAR2(1000) := '';

    V_QUERY_OPTION   VARCHAR(1000);
    V_SEQ               INT := 0;
BEGIN
--    v_memo := v_memo || ' '; -- 추가 메모 입력
    SP_W_COM_USE_LOG(p_lang, p_plant, p_rdc_code, p_user_id, p_user_ip, p_pgm, p_proc, p_case, p_query_option, v_memo, p_out_result, p_out_msg);

    SELECT JSON_VALUE(p_query_option, '$.IPADDRESS') INTO IPADDRESS FROM DUAL;
    SELECT JSON_VALUE(p_query_option, '$.PDANO')     INTO PDANO     FROM DUAL;
    SELECT JSON_VALUE(p_query_option, '$.PLTNO')     INTO PLTNO     FROM DUAL;
    SELECT JSON_VALUE(p_query_option, '$.LOC1')      INTO LOC1      FROM DUAL;
    SELECT JSON_VALUE(p_query_option, '$.LOC2')      INTO LOC2      FROM DUAL;
    SELECT JSON_VALUE(p_query_option, '$.LOC3')      INTO LOC3      FROM DUAL;

    IF P_CASE = 'SELECT' THEN -- 다중 입력값 회신(ECHO)
        P_OUT_RESULT :='OK'; --//OK //ERR //INFO
        P_OUT_MSG    :='입력값 회신(NO INSERT)';

        OPEN P_OUT_CURSOR FOR
            SELECT IPADDRESS, PDANO, PLTNO, LOC1, LOC2, LOC3
              FROM JSON_TABLE(P_QUERY_OPTION, '$[*]'  COLUMNS(IPADDRESS, PDANO, PLTNO, LOC1, LOC2, LOC3))
            ;
        RETURN;
    END IF;

    IF P_CASE NOT IN ('SELECT', 'INSERT', 'SAVE') THEN
        V_ERRTYPE := 'ERRM0';
        V_ERRDESC := 'UNKNOWN CASE : ' || NVL(P_CASE, 'NULL');
        RAISE USER_ERROR;
    END IF;

----여기부터 테스트
--P_OUT_RESULT :='OKM'; --//OK //ERR //INFO
--P_OUT_MSG :=SF_GET_LOCALE_MESSAGE(P_LANG, 'TEST...') ;
--OPEN P_OUT_CURSOR FOR SELECT P_OUT_RESULT AS MSG_TYPE, P_OUT_MSG AS MSG_TEXT FROM DUAL;
--RETURN;
----여기까지  테스트

    V_SEQ := 0;
    FOR C_IN IN (
            SELECT IPADDRESS, PDANO, PLTNO, LOC1, LOC2, LOC3
              FROM JSON_TABLE(P_QUERY_OPTION, '$[*]'  COLUMNS(IPADDRESS, PDANO, PLTNO, LOC1, LOC2, LOC3))
    )
    LOOP
        V_SEQ := V_SEQ +1; -- 처리행

        --V_YYYYMMDD := to_char(V_LOCDATE,'YYYYMMDD');
        V_YYYYMMDD := SF_GETPOSTINGDATE; -- 마감기준 적용
        /*
            목적 : P/T 전체이동
            테이블 : TB_STK_PLTIO

            FR_PLT 가 실 파렛트면 이동처리 TO_PLT<=FR_PLT
            FR_PLT가  가상 파렛트면 ... 이동LOC의 매핑된 가상파렛트 로 TO_PLT

            TO_FLT 가 가상 파렛트면 ... 이동LOC의 매핑된 가상파렛트 로 TO_PLT

            -- Rack에서 나오는 경우, 실파렛트 번호 가지고 있음.
            -- TO_loc가 가상이면 가상PLT 매핑
            -- 비상출고대로 이동시... 기존 PLT 유지

        */

--        p_plant      := p_plant;
        v_WHOUSECODE := LOC1;
        v_ADDR       := LOC2||LOC3;

        IF NVL(SF_W_GET_CODENAME(P_LANG, P_PLANT, 'CODE_RDC', P_RDC_CODE, 'PLT_NO_USE', '', ''), 'N') <> 'Y' THEN  -- 가상팔레트 조회 선조건 sjkim
            --//가상파렛트는 전체이동 못함
            v_cnt:=0;
            SELECT COUNT(1)
              INTO v_cnt
              FROM TB_STK_PLTM T
             WHERE T.PLANT       = P_PLANT    -- ADD PLANT 20231227 SOO
               AND T.PLT_NO      = PLTNO
               AND T.WHOUSE_CODE = v_WHOUSECODE -- LOC1
               AND CATEGORY_GBN  ='1' -- 1일반, 2가상, 3전산조정
            ;

            IF v_cnt = 0 THEN
                V_ERRTYPE := 'ERRM01';
                V_ERRDESC := SF_GET_LOCALE_MESSAGE (P_LANG, 'Row') || V_SEQ || '-' || SF_GET_LOCALE_MESSAGE (P_LANG, '[Check PLT-NO] Not allowed to MOVE (No_data or Virtual_rack)');
                RAISE USER_ERROR;
    --           v_errDesc:='[Check PLT-NO] Not allowed to MOVE (No_data or Virtual_rack)';
            END IF;
        END IF;

        --// 이동하려는 PLT의 RDC와 to창고의 RDC 같아야 한다.
        v_cnt:=0;

        SELECT COUNT(1)
          INTO v_cnt
          FROM TB_BAS_LOC_CODE T
         WHERE T.PLANT       = P_PLANT    -- ADD PLANT 20231227 SOO
           AND T.WHOUSE_CODE = V_WHOUSECODE
           AND T.RDC_CODE    = P_RDC_CODE -- UPDATE PLANT 20231227 SOO
--           IN
--               (SELECT RDC
--                  FROM TB_STK_PLTM
--                 WHERE PLANT  = P_PLANT    -- ADD PLANT 20231227 SOO
--                   AND PLT_NO = PLTNO
--               )
        ;
        IF v_cnt = 0 THEN
            V_ERRTYPE := 'ERRM02';
            V_ERRDESC := SF_GET_LOCALE_MESSAGE (P_LANG, 'Row') || V_SEQ || '-' || SF_GET_LOCALE_MESSAGE (P_LANG, '[Check RDC] Not allowed to move ... different RDC');
            RAISE USER_ERROR;
--           v_errDesc:='[Check RDC] Not allowed to move ... different RDC';
        END IF;


        --// STG-ARA 로 바로 이동은 못함
        v_cnt:=0;

        SELECT COUNT(1)
          INTO V_CNT
          FROM TB_BAS_LOC_ADDR T
         WHERE T.PLANT       = P_PLANT    -- ADD PLANT 20231227 SOO
           AND T.RDC_CODE    = P_RDC_CODE -- ADD 20240621 SOO
           AND T.WHOUSE_CODE = V_WHOUSECODE
           AND T.ADDR        = V_ADDR
           AND T.ADDR_TYPE NOT IN ('0','2') -- 0 IN , 1 BIN , 2 OUT, 3 SPECIAL
        ;
        IF v_cnt = 0 THEN
            V_ERRTYPE := 'ERRM03';
            V_ERRDESC := SF_GET_LOCALE_MESSAGE (P_LANG, 'Row') || V_SEQ || '-' || SF_GET_LOCALE_MESSAGE (P_LANG, '[Check Location] Not allowed to move ... STG-ARA');
            RAISE USER_ERROR;
--            v_errDesc:='[Check Location] Not allowed to move ... STG-ARA';
        END IF;

        --//
        SELECT WMSRDC.SF_CHK_MOVEQTY2(P_PLANT, P_RDC_CODE, PLTNO)
          INTO v_RETURN
          FROM DUAL
        ;

        IF v_RETURN = 'N' THEN
            V_ERRTYPE := 'ERRM04';
            V_ERRDESC := SF_GET_LOCALE_MESSAGE (P_LANG, 'Row') || V_SEQ || '-' || SF_GET_LOCALE_MESSAGE (P_LANG, '[LOC] Not enough qty to move');
            RAISE USER_ERROR;
--            v_errDesc:='[LOC] Not enough qty to move';
           --GOTO GOTO_TAG1;
        END IF;




          --// 사전체크 사항
             -- 입력한 Parm 값이 정상인지
             -- 입고할 대상 파렛트가 정상 인지
             -- 대상 수량 이 남아  있는지... 오버인지

        --입력값 체크
        V_QUERY_OPTION :=
            '{
                "WHOUSE":"' || v_WHOUSECODE || '"' ||
             ' ,"ADDR":"'   || v_ADDR       || '"' ||
             ' ,"PLTNO":"'  || PLTNO   || '"' ||
             '
             }';

        -- 플시저 수정 20231221 SOO
        SP_W_OTB_MOVE00_S01(P_LANG, P_PLANT, P_RDC_CODE, P_USER_ID, P_USER_IP, P_PGM, P_PROC, P_CASE, V_QUERY_OPTION, V_ERRTYPE, V_ERRDESC, P_OUT_CURSOR);
--        SP_PDA_MOVE00_S01 ( P_PLANT, p_rdc_code, v_WHOUSECODE, v_Addr, PLTNO, v_errType ,v_errDesc  ) ;  -- 체크
          IF v_errType = 'ERR' THEN
            V_ERRTYPE := 'ERRM09';
            V_ERRDESC := v_errDesc || SF_GET_LANG(P_LANG, 'Row') || ' ' || V_SEQ || ', '
                                   || 'PLT '|| PLTNO ;
            RAISE USER_ERROR;
          END IF;

        --//
        v_MOVNO := SF_W_GET_NEXT_SEQ(P_PLANT, 'MOVNO','','',''); -- ADD PLANT 20231227 SOO
        v_MOVTYPE :='10'; --전체이동

        v_JOBINFO := 'PLANT:'      || P_PLANT      || '/' ||
                     'PLTNO:'      || PLTNO   || '/' ||
                     'MOVNO:'      || v_MOVNO      || '/' ||
                     'MOVTYPE:'    || v_MOVTYPE    || '/' ||
                     'WHOUSECODE:' || v_WHOUSECODE || '/' ||
                     'ADDR:'       || v_ADDR       || '/' ||
                     'PDANO:'      || PDANO;

        --이동 이력에 데이터 입력
        INSERT INTO TB_STK_PLTIO
              (
                PLANT
              , SRC_PLANT
              , MOVNO
              , MOVSEQ
              , MOVTYPE
              , MOVDAT
              , FR_PLTNO
              , FR_PLTSEQ
              , FR_WHOUSE
              , FR_ADDR
              , TO_PLTNO
              , TO_PLTSEQ
              , TO_WHOUSE
              , TO_ADDR
              , ITEM_CODE
              , GRADE
              , OWNGBN
              , QTY
              , PACKED
              , PACKCLR
              , PRODDAT
              , JPSTS
              , JPSTS_CODE
              , OTSTS
              , OT_DESC
              , DESC_NOTE
              , F_DATE
              , F_AUTHOR
              , L_DATE
              , L_AUTHOR
              , USE_FLAG
              , TRG_FLAG
              , IP_ADDRESS
              , PDA_NO
              , L_DTIME
              , OLD_PACKCLR
              , IN_TYPE
              , INDAT
              , rdc
              )
          SELECT P_PLANT                               --PLANT
               , A.SRC_PLANT                           --SRC_PLANT
               , v_MOVNO                               --MOVNO
               , ROW_NUMBER() OVER(ORDER BY A.PLT_SEQ) --MOVSEQ
               , v_MOVTYPE                             --MOVTYPE
               , V_YYYYMMDD                            --MOVDAT
               , A.PLT_NO                              --FR_PLTNO
               , A.PLT_SEQ                             --FR_PLTSEQ
               , B.WHOUSE_CODE                         --FR_WHOUSE
               , B.PLT_ADDR                            --FR_ADDR
               , A.PLT_NO                              --TO_PLTNO     ---------- TARGET PLTNO
               , A.PLT_SEQ                             --TO_PLTSEQ    ---------- 있는값 + 1 증가
               , v_WHOUSECODE                          --TO_WHOUSE
               , v_ADDR                                --TO_ADDR
               , A.ITEM_CODE                           --ITEM_CODE
               , A.GRADE                               --GRADE
               , NVL(A.OWNGBN, 'H000')                 --OWNGBN
               , A.QTY                                 --QTY
               , NVL(A.PACKED, 'N')                    --PACKED
               , NVL(A.PACKCLR, 'P1')                  --PACKCLR
               , A.PRODDAT                             --PRODDAT
               , A.JPSTS                               --JPSTS
               , A.JPSTS_CODE                          --JPSTS_CODE
               , NVL(A.OTSTS, '0')                     --OTSTS
               , A.OT_DESC                             --OT_DESC
               , B.DESC_NOTE                           --DESC_NOTE
               , TO_CHAR(V_LOCDATE, 'YYYYMMDD')          --F_DATE
               , p_user_ip                             --F_AUTHOR
               , TO_CHAR(V_LOCDATE, 'YYYYMMDD')          --L_DATE
               , p_user_ip                             --L_AUTHOR
               , 'Y'                                   --USE_FLAG
               , 'Y'                                   --TRG_FLAG
               , IPADDRESS                        --IP_ADDRESS
               , PDANO                            --PDA_NO
               , TO_CHAR(V_LOCDATE, 'YYYYMMDDHH24MISS')  --L_DTIME
               , NVL(A.PACKCLR, 'P1')                  --OLD_PACKCLR
               , A.IN_TYPE                             --IN_TYPE
               , A.INDAT                               --INDAT
               , b.rdc
            FROM TB_STK_PLTD A
               , TB_STK_PLTM B
           WHERE 1 = 1
             AND A.PLANT  = B.PLANT  -- 확인 PLANT 20231227 SOO
             AND A.PLT_NO = B.PLT_NO
             AND A.PLANT  = P_PLANT  -- 확인 PLANT 20231227 SOO
             AND A.PLT_NO = PLTNO
             AND EXISTS
                 (SELECT 1
                    FROM TB_BAS_LOC_ADDR
                   WHERE PLANT       = B.PLANT  -- 확인 PLANT 20231227 SOO
                     AND RDC_CODE    = B.RDC    -- ADD RDC   20231227 SOO
                     AND WHOUSE_CODE = B.WHOUSE_CODE
                         --AND ADDR_TYPE   = '1'
                     AND ADDR = B.PLT_ADDR
                 )
        ORDER BY A.PLT_SEQ;

       -- PICKMOV 삭제처리
         FOR C_1 IN (
             SELECT PLANT, PLT_NO, PLT_SEQ, ORDNO, ORDSEQ, PICKNO, MOVNO, MOVSEQ, QTY, QTY as movqty
               FROM TB_STK_PLTD A
              WHERE A.PLANT = P_PLANT    -- 확인 PLANT 20231227 SOO
                AND A.PLT_NO = PLTNO
         )
         LOOP
             IF nvl(C_1.ORDNO,' ')=' ' or nvl(C_1.PICKNO,' ')=' ' or nvl(C_1.MOVNO,' ')=' ' then
               null;
               -- SKIP
             ELSE
                 IF nvl(C_1.QTY,0) = nvl(C_1.movqty,0) THEN
                   -- 삭제 FLAG 처리
                    UPDATE TB_OTB_PICKMOV T
                       SET T.USE_FLAG ='D'
                         , T.PICKDONE ='D'
                     WHERE T.PLANT    = C_1.PLANT -- 확인 PLANT 20231227
                       AND T.ORDNO    = C_1.ORDNO
                       AND T.ORDSEQ   = C_1.ORDSEQ
                       AND T.PICKNO   = C_1.PICKNO
                       AND T.MOVNO    = C_1.MOVNO
                       AND T.MOVSEQ   = C_1.MOVSEQ
                       AND T.FR_PLTNO = C_1.PLT_NO
                    ;
                 ELSE
                   -- 수량업데이트
                    UPDATE TB_OTB_PICKMOV T
                       SET T.MOVE_QTY = T.MOVE_QTY - NVL(C_1.MOVQTY, 0) -- 원래 이동수량에서 지금 이동한 수량 뺌
                     WHERE T.PLANT    = C_1.PLANT  -- 확인 PLANT 20231227
                       AND T.FR_PLTNO = C_1.PLT_NO
                       AND T.ORDNO    = C_1.ORDNO
                       AND T.ORDSEQ   = C_1.ORDSEQ
                       AND T.PICKNO   = C_1.PICKNO
                       AND T.MOVNO    = C_1.MOVNO
                       AND T.MOVSEQ   = C_1.MOVSEQ ;
                 END IF;
             END IF;
         ENd LOOP;



        --PLT M  업데이트
        UPDATE TB_STK_PLTM T
           SET WHOUSE_CODE = V_WHOUSECODE
             , PLT_ADDR    = V_ADDR
             , T.ORDNO     = NULL
             , T.ORDSEQ    = NULL
             , T.L_AUTHOR  = P_USER_IP
             , T.L_DATE    = V_LOCDATE
         WHERE PLANT       = P_PLANT -- 확인 PLANT 20231227
           AND PLT_NO      = PLTNO ;

        --PLT D 업데이트
        UPDATE TB_STK_PLTD T
           SET T.ORDNO    = NULL
             , T.ORDSEQ   = NULL
             , T.PICKNO   = NULL
             , T.MOVNO    = NULL
             , T.MOVSEQ   = NULL
             , T.L_AUTHOR = P_USER_IP
             , T.L_DATE   = V_LOCDATE
         WHERE PLANT      = P_PLANT -- 확인 PLANT 20231227
           AND PLT_NO     = PLTNO ;

        <<GOTO_TAG1>>
        COMMIT;

        --PDA 로그 남김
        SP_W_PDA_MOBILE_JOBLOG_P01(P_PLANT, IPADDRESS, PDANO, p_user_ip, 'Y', p_pgm, v_JBONAME || '/' || 'SUCCESS', v_JOBINFO ) ;
    END LOOP;

    p_out_result :='OK'; --//OK //ERR //INFO
    p_out_msg    :='OK';

-- 'INSERT' 'UPDATE' 'DELETE' 의 경우
    OPEN p_out_cursor FOR
        SELECT p_out_result AS MSG_TYPE, p_out_msg AS MSG_TEXT FROM DUAL;

EXCEPTION
    WHEN USER_ERROR THEN
        p_out_result := v_errType;
        p_out_msg    := v_errDesc;
        ROLLBACK;
        OPEN p_out_cursor FOR SELECT p_out_result AS MSG_TYPE, p_out_msg AS MSG_TEXT FROM DUAL;
    WHEN OTHERS THEN
        p_out_result := 'ERR';
        p_out_msg    := SQLERRM;
        ROLLBACK;
        OPEN p_out_cursor FOR SELECT p_out_result AS MSG_TYPE, p_out_msg AS MSG_TEXT FROM DUAL; -- FAIL
END;