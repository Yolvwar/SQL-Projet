// Niveau 1 - Requête SQL

// add_transport_type

CREATE FUNCTION add_transport_type( id_mdt char(3), line_name varchar(32), max_capacity integer, travel_time integer )
RETURNS boolean AS $$
BEGIN
    INSERT INTO transportation_means (id_mdt, line_name, max_capacity, travel_time)
    VALUES (id_mdt, line_name, max_capacity, travel_time);

RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// add_zone

CREATE FUNCTION add_zone(name varchar(32), price float)
RETURNS boolean AS $$
BEGIN
 IF price <= O THEN
    RAISE EXCEPTION 'Un prix ne peut être ni nul ni négatif';
END IF;

INSERT INTO zone (zone_name, zone_price)
VALUES (name, price);

RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// add_station

CREATE FUNCTION add_station(id_station integer, station_name varchar(64), station_municipality varchar(64), zone_id integer, municipality_id integer)
RETURNS boolean AS $$
BEGIN

IF NOT EXISTS (SELECT * FROM zone WHERE zone_number = zone_id) THEN
    RAISE EXCEPTION 'La zone n''existe pas';
END IF;

IF NOT EXISTS (SELECT * FROM municipality WHERE id = municipality_id) THEN
    RAISE EXCEPTION 'La municipality n''existe pas';
END IF;

INSERT INTO station (id_station, station_name, station_municipality, zone_id, municipality_id)
VALUES (id_station, station_name, station_municipality, zone_id, municipality_id);

RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// add_line

CREATE FUNCTION add_station_to_line(station INT, line VARCHAR(3), pos INT)
RETURNS boolean AS $$
BEGIN
  IF NOT EXISTS (SELECT * FROM station WHERE id_station = station) THEN
    RAISE EXCEPTION 'La station n''existe pas';
  END IF;

  IF NOT EXISTS (SELECT * FROM line WHERE code = line) THEN
    RAISE EXCEPTION 'La line n''existe pas';
  END IF;

  IF EXISTS (SELECT * FROM line_Station WHERE station_id = station AND line_id = (SELECT id FROM line WHERE code = line)) THEN
    RAISE EXCEPTION 'La station est déjà présente dans la line';
  END IF;

  IF EXISTS (SELECT * FROM line_Station WHERE position = pos AND line_id = (SELECT id FROM line WHERE code = line)) THEN
    RAISE EXCEPTION 'La position est déjà occupée par une autre station';
  END IF;

  INSERT INTO line_Station (station_id, line_id, position)
  VALUES (station, (SELECT id FROM line WHERE code = line), pos);

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// views 

CREATE VIEW view_transport_50_300_users AS
SELECT line_name
FROM transportation_means
WHERE max_capacity BETWEEN 50 AND 300
ORDER BY line_name;

CREATE VIEW view_stations_from_paris AS
SELECT station_name
FROM station
WHERE LOWER(station_municipality) = 'paris'
ORDER BY station_name;

CREATE VIEW view_stations_zones AS
SELECT station.station_name, zone.zone_name
FROM station
JOIN zone ON station.zone_id = zone.zone_number
ORDER BY zone.zone_number, station.station_name;

CREATE VIEW view_nb_station_type AS
SELECT transportation_means.line_name AS type, COUNT(station.id_station) AS stations
FROM transportation_means
JOIN station ON transportation_means.id_mdt = station.transportation_mode_id
GROUP BY transportation_means.line_name
ORDER BY stations DESC, transportation_means.line_name;

CREATE VIEW view_line_duration AS
SELECT transportation_means.line_name AS type, line.code AS line, transportation_means.travel_time AS minutes
FROM transportation_means
JOIN line ON transportation_means.id_mdt = line.transportation_mode_id
ORDER BY transportation_means.line_name, line.code;

CREATE VIEW view_station_capacity AS
SELECT station.station_name AS station, transportation_means.max_capacity AS capacity
FROM station
JOIN transportation_means ON station.transportation_mode_id = transportation_means.id_mdt
WHERE LOWER(station.station_name) LIKE 'A%'
ORDER BY station.station_name, transportation_means.max_capacity;

// procédures 

CREATE FUNCTION list_station_in_line(line_code VARCHAR(3))
RETURNS SETOF VARCHAR(64) AS $$
BEGIN
  RETURN QUERY
  SELECT station.station_name
  FROM station
  JOIN line_Station ON station.id_station = line_Station.station_id
  JOIN line ON line_Station.line_id = line.id
  WHERE line.code = line_code
  ORDER BY line_Station.position;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION list_types_in_zone(zone INT)
RETURNS SETOF VARCHAR(32) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT transportation_means.line_name
  FROM transportation_means
  JOIN station ON transportation_means.id_mdt = station.transportation_mode_id
  WHERE station.zone_id = zone
  ORDER BY transportation_means.line_name;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION get_cost_travel(station_start INT, station_end INT)
RETURNS FLOAT AS $$
DECLARE
  start_zone INT;
  end_zone INT;
  total_cost FLOAT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM station WHERE id_station = station_start) OR
     NOT EXISTS (SELECT 1 FROM station WHERE id_station = station_end) THEN
    RETURN 0;
  END IF;

  SELECT zone_id INTO start_zone FROM station WHERE id_station = station_start;
  SELECT zone_id INTO end_zone FROM station WHERE id_station = station_end;

// utiliser GREATEST et least 
  SELECT SUM(zone_price) INTO total_cost
  FROM zone
  WHERE zone_number BETWEEN LEAST(start_zone, end_zone) AND GREATEST(start_zone, end_zone);

  RETURN total_cost;
END;
$$ LANGUAGE plpgsql;