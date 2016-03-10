/*** Procedure to populate ref_date ***/

DROP PROCEDURE IF EXISTS datetable
DELIMITER //
CREATE PROCEDURE datetable()
BEGIN
DECLARE strt date;
DECLARE season integer;
SET strt = str_to_date('1/1/2001','%c/%e/%Y');
SET season = 2001;

WHILE strt < str_to_date('1/1/2024','%c/%e/%Y') DO
	IF month(strt) >= 10.0 THEN 
		SET season =  year(strt); 
	ELSE 
		SET season =  year(strt) -1; 
	END IF;
	INSERT INTO stg.ref_date(game_date,game_year, game_month, game_day, season_year)
    VALUES(strt, year(strt),month(strt),day(strt),season);
    SET strt = adddate(strt,1);
END WHILE;
END //
DELIMITER ;
