/* Tabellen und Views für das Projekt

Gutscheine für Travel Tide Kunden ermitteln (automatisierte Berechnung)

*/

-- 1. Parameter Tabelle für Projektvarianten
-- 2. Ergebnistabelle für die Projekttests

-- DROP TABLE pj_solution; -- DROP wenn Neustart
-- DROP TABLE pj_param; -- DROP wenn Neustart

CREATE TABLE PJ_PARAM (
  para_id SERIAL PRIMARY KEY,
  active BOOL NOT NULL DEFAULT FALSE,
  para_name TEXT,
  variant TEXT,
  dimension INT,
  para_value TEXT,
  typ TEXT
);

CREATE TABLE PJ_SOLUTION (
  solution_id INT NOT NULL,
  user_id INT NOT NULL,
  sol_name TEXT,
  sol_value TEXT,
  para_name TEXT,
CONSTRAINT sol_usr PRIMARY KEY (solution_id, user_id)
);

-- Startdaten einfügen und Aktivieren
TRUNCATE TABLE pj_param RESTART IDENTITY;

INSERT INTO pj_param (para_name, variant, dimension, para_value, typ)
VALUES
    ('projekt_date', 'default', 1, '2024-01-01', 'Datum'),
    ('projekt_date', 'test_1', 1, '2024-01-01', 'Datum'),
    ('projekt_date', 'test_2', 1, '2024-01-01', 'Datum'),
    ('startdate', 'default', 1, '2023-01-04', 'Datum'),
		('session_min', 'default', 1, '7', 'Anzahl'),
		('click_limit', 'default', 1, '100', 'Anzahl'),
		('startdate', 'test_1', 1, '2022-10-01', 'Datum'),
		('session_min', 'test_1', 1, '5', 'Anzahl'),
		('click_limit', 'test_1', 1, '200', 'Anzahl'),
		('startdate', 'test_2', 1, '2022-01-01', 'Datum'),
		('session_min', 'test_2', 1, '3', 'Anzahl'),
		('click_limit', 'test_2', 1, '300', 'Anzahl'),
    ('summer_season_start','generell',1, '0615','MMTT'),
    ('summer_season_end','generell',1, '3009','MMTT'),
    ('winter_season_start','generell',1, '1115','MMTT'),
    ('winter_season_end','generell',1, '3103','MMTT')
    ('summer_season_start','generell',1, '0615','MMTT'),
    ('summer_season_end','generell',1, '3009','MMTT'),
    ('winter_season_start','generell',1, '1115','MMTT'),
    ('winter_season_end','generell',1, '3103','MMTT')
;

UPDATE pj_param
SET active = FALSE;

UPDATE pj_param
SET active = TRUE
WHERE variant = 'generell' or variant = 'default';


-- Views für die Projekt Datenbasis

-- pj_session_base zusammenführen von Quelldaten,
--         filtern von Datenfehlern und ,
--         transformation von NULL Werten und ggf. Wertebereiche
DROP VIEW PJ_USER_BASE;
DROP VIEW PJ_NC_TRIPS;
DROP VIEW PJ_SESSION_BASE;

CREATE OR REPLACE VIEW PJ_SESSION_BASE AS
SELECT
	S.SESSION_ID,
	S.USER_ID,
	S.TRIP_ID,
	S.SESSION_START,
	S.SESSION_END,
	S.SESSION_END - S.SESSION_START AS SESSION_DURATION,
	S.FLIGHT_DISCOUNT,
  COALESCE (S.FLIGHT_DISCOUNT_AMOUNT, 0) AS FLIGHT_DISCOUNT_AMOUNT,
  S.HOTEL_DISCOUNT,
  COALESCE (S.HOTEL_DISCOUNT_AMOUNT, 0) AS HOTEL_DISCOUNT_AMOUNT,
	S.FLIGHT_BOOKED::INT AS FLIGHT_BOOKED,
	S.HOTEL_BOOKED::INT AS HOTEL_BOOKED,
  -- Outline für Clicks auf ein parametrisiertes Minimum setzen
	LEAST (S.PAGE_CLICKS, (SELECT para_value::INTEGER FROM pj_param WHERE active AND para_name = 'click_limit')) PAGE_CLICKS,
	S.CANCELLATION,
	F.ORIGIN_AIRPORT,
	F.DESTINATION,
	F.DESTINATION_AIRPORT,
	F.SEATS,
	F.RETURN_FLIGHT_BOOKED,
	F.DEPARTURE_TIME,
	F.RETURN_TIME,
	F.CHECKED_BAGS,
	F.TRIP_AIRLINE,
	F.DESTINATION_AIRPORT_LAT,
	F.DESTINATION_AIRPORT_LON,
  F.BASE_FARE_USD,
  F.BASE_FARE_USD * (1 - S.FLIGHT_DISCOUNT_AMOUNT) AS MONEY_SPENT_PER_FLIGHT,
  F.BASE_FARE_USD * (1 - S.FLIGHT_DISCOUNT_AMOUNT) / F.SEATS AS MONEY_SPENT_PER_SEAT,
  F.RETURN_TIME::DATE - F.DEPARTURE_TIME::DATE AS FLIGHT_DURATION,
	H.HOTEL_NAME,
  GREATEST (H.NIGHTS, 1) AS NIGHTS, -- Outline Übernachtungen <= 0 auf 1 setzen
	H.ROOMS,
	H.CHECK_IN_TIME,
	H.CHECK_OUT_TIME,
	H.HOTEL_PER_ROOM_USD,
  H.HOTEL_PER_ROOM_USD * H.ROOMS * H.NIGHTS * (1 - S.HOTEL_DISCOUNT_AMOUNT) AS MONEY_SPENT_PER_HOTEL,
  H.CHECK_OUT_TIME::DATE - H.CHECK_IN_TIME::DATE AS HOTEL_DURATION,
	U.BIRTHDATE,
	U.GENDER,
	U.MARRIED,
	U.HAS_CHILDREN,
	U.HOME_COUNTRY,
	U.HOME_CITY,
	U.HOME_AIRPORT,
	U.HOME_AIRPORT_LAT,
	U.HOME_AIRPORT_LON,
	U.SIGN_UP_DATE,
  LEAST(F.DEPARTURE_TIME, H.CHECK_IN_TIME) - (S.SESSION_START) AS TIME_AFTER_BOOKING
FROM
	(
		SELECT
			SQ.USER_ID
		FROM
			(
				SELECT
					SS.SESSION_ID,
					SS.USER_ID
				FROM
					SESSIONS AS SS
				WHERE
					SS.SESSION_START::DATE > (SELECT para_value::DATE FROM pj_param WHERE active AND para_name = 'startdate')
			) AS SQ
		GROUP BY
			SQ.USER_ID
		HAVING
			COUNT(SQ.SESSION_ID) > (SELECT para_value::INTEGER from pj_param WHERE active AND para_name = 'session_min')
	) USERS_X
	JOIN SESSIONS S ON USERS_X.USER_ID = S.USER_ID
	JOIN USERS U ON S.USER_ID = U.USER_ID
	LEFT JOIN FLIGHTS F ON S.TRIP_ID = F.TRIP_ID
	LEFT JOIN HOTELS H ON S.TRIP_ID = H.TRIP_ID

WHERE
	S.SESSION_START::DATE > (SELECT para_value::DATE FROM pj_param WHERE active AND para_name = 'startdate')
;

-- pg_trips nur durchgeführte Trips ohne 'censelations'

CREATE OR REPLACE VIEW PJ_NC_TRIPS AS
SELECT
	*,
  CASE EXTRACT(MONTH FROM CASE
            WHEN flight_booked = 1 THEN departure_time
            ELSE check_in_time
          END)
    WHEN 12 THEN 'winter'
    WHEN 1 THEN 'winter'
    WHEN 2 THEN 'winter'
    WHEN 3 THEN 'spring'
    WHEN 4 THEN 'spring'
    WHEN 5 THEN 'spring'
    WHEN 6 THEN 'summer'
    WHEN 7 THEN 'summer'
    WHEN 8 THEN 'summer'
    WHEN 9 THEN 'fall'
    WHEN 10 THEN 'fall'
    WHEN 11 THEN 'fall'
END AS season

FROM
	PJ_SESSION_BASE AS S
WHERE
	TRIP_ID NOT IN (
		SELECT
			TRIP_ID
		FROM
			PJ_SESSION_BASE
		WHERE
			CANCELLATION = TRUE
	)
;


-- pg_features view für die Auswertung in verschieden Methoden

CREATE OR REPLACE VIEW PJ_USER_BASE AS
SELECT
	u1.user_id,
	u1.num_sessions,
	u1.avg_session_duration,
	u1.std_session_duration,
	u1.avg_clicks,
	u1.bookings,
	u2.canceled_trips,
	u3.num_trips,
	u3.destinatons,
	u3.avg_checked_bags,
	u3.avg_seats,
	u3.avg_nights,
	u3.avg_rooms,
	u3.std_nights,
	u3.num_flights,
	u3.num_hotels,
	u3.total_money_spent_per_flight,
	u3.avg_money_spent_per_flight,
	u3.avg_money_spent_per_seat,
	u3.total_money_spent_per_hotel,
	u3.avg_money_spent_per_hotel,
	u3.avg_time_after_booking,
	u3.season_winter,
	u3.season_spring,
	u3.season_summer,
	u3.season_fall,
	u4.gender,
	u4.married,
	u4.has_children,
	u4.home_country,
	u4.age,
	u4.MEMBER_DAYS
FROM (SELECT s.user_id,
		COUNT (s.session_id) AS num_sessions,
		AVG (s.session_duration) AS avg_session_duration,
		STDDEV_SAMP (EXTRACT (EPOCH FROM (s.session_duration))) AS std_session_duration,
		AVG (s.page_clicks) AS avg_clicks,
		COUNT (DISTINCT trip_id) AS bookings
	FROM pj_session_base s
	GROUP BY s.user_id) u1
LEFT JOIN (SELECT t.user_id,
		COUNT (DISTINCT t.trip_id) AS canceled_trips
	FROM (SELECT ss.user_id, ss.trip_id FROM pj_session_base ss WHERE cancellation = TRUE) t
	GROUP BY t.user_id) u2
	ON u1.user_id = u2.user_id
LEFT JOIN (SELECT n.user_id,
		COUNT (n.trip_id) AS num_trips,
		COUNT (DISTINCT n.destination) AS destinatons,
		AVG (n.checked_bags) AS avg_checked_bags,
		AVG (n.seats) AS avg_seats,
		AVG (n.nights) AS avg_nights,
		AVG (n.rooms) AS avg_rooms,
		STDDEV_SAMP (n.nights) AS std_nights,
		SUM (n.flight_booked) AS num_flights,
		SUM (n.hotel_booked) AS num_hotels,
		SUM (n.money_spent_per_flight) AS total_money_spent_per_flight,
		AVG (n.money_spent_per_flight) AS avg_money_spent_per_flight,
		AVG (n.money_spent_per_seat) AS avg_money_spent_per_seat,
		SUM (n.money_spent_per_hotel) AS total_money_spent_per_hotel,
		AVG (n.money_spent_per_hotel) AS avg_money_spent_per_hotel,
		AVG (n.time_after_booking) AS avg_time_after_booking,
		COUNT (CASE WHEN n.season = 'winter' THEN 1 END) AS season_winter,
		COUNT (CASE WHEN n.season = 'spring' THEN 1 END) AS season_spring,
		COUNT (CASE WHEN n.season = 'summer' THEN 1 END) AS season_summer,
		COUNT (CASE WHEN n.season = 'fall' THEN 1 END) AS season_fall
		-- avg distance km
		-- avg price per km
	FROM pj_nc_trips n
	GROUP BY n. user_id) u3
	ON u1.user_id = u3.user_id
LEFT JOIN (SELECT u.user_id,
		u.gender,
		u.married::INT,
		u.has_children::INT,
		u.home_country,
		((SELECT para_value::DATE FROM pj_param WHERE active AND para_name = 'projekt_date') - u.birthdate) / 365 AS AGE,
		((SELECT para_value::DATE FROM pj_param WHERE active AND para_name = 'projekt_date')  - U.SIGN_UP_DATE) AS MEMBER_DAYS
	FROM users u) u4
	ON u1.user_id = u4.user_id
;



-- (SELECT para_value::DATE FROM pj_param WHERE active AND para_name = 'project_date')::TIMESTAMP - S.BIRTHDATE) / 365 AS AGE
-- (SELECT para_value::DATE FROM pj_param WHERE active AND para_name = 'project_date')::TIMESTAMP - S.SIGN_UP_DATE) AS MEMBER_TIME
