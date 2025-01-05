// Niveau 1 - Requête SQL

// add_transport_type

CREATE FUNCTION add_transport_type( id_mdt char(3), line_name varchar(32), max_capacity integer, travel_time integer )
RETURNS boolean AS $$
BEGIN
    INSERT INTO moyens_de_transport (id_mdt, line_name, max_capacity, travel_time)
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

CREATE FUNCTION add_station(id_station integer, station_name varchar(64), station_commune varchar(64), zone_id integer, commune_id integer)
RETURNS boolean AS $$
BEGIN

IF NOT EXISTS (SELECT * FROM zone WHERE zone_number = zone_id) THEN
    RAISE EXCEPTION 'La zone n''existe pas';
END IF;

IF NOT EXISTS (SELECT * FROM commune WHERE id = commune_id) THEN
    RAISE EXCEPTION 'La commune n''existe pas';
END IF;

INSERT INTO station (id_station, station_name, station_commune, zone_id, commune_id)
VALUES (id_station, station_name, station_commune, zone_id, commune_id);

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

  IF NOT EXISTS (SELECT * FROM ligne WHERE code = line) THEN
    RAISE EXCEPTION 'La ligne n''existe pas';
  END IF;

  IF EXISTS (SELECT * FROM Ligne_Station WHERE station_id = station AND ligne_id = (SELECT id FROM ligne WHERE code = line)) THEN
    RAISE EXCEPTION 'La station est déjà présente dans la ligne';
  END IF;

  IF EXISTS (SELECT * FROM Ligne_Station WHERE position = pos AND ligne_id = (SELECT id FROM ligne WHERE code = line)) THEN
    RAISE EXCEPTION 'La position est déjà occupée par une autre station';
  END IF;

  INSERT INTO Ligne_Station (station_id, ligne_id, position)
  VALUES (station, (SELECT id FROM ligne WHERE code = line), pos);

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// views 

CREATE VIEW view_transport_50_300_users AS
SELECT line_name
FROM moyens_de_transport
WHERE max_capacity BETWEEN 50 AND 300
ORDER BY line_name;

CREATE VIEW view_stations_from_paris AS
SELECT station_name
FROM station
WHERE LOWER(station_commune) = 'paris'
ORDER BY station_name;

CREATE VIEW view_stations_zones AS
SELECT station.station_name, zone.zone_name
FROM station
JOIN zone ON station.zone_id = zone.zone_number
ORDER BY zone.zone_number, station.station_name;

CREATE VIEW view_nb_station_type AS
SELECT moyens_de_transport.line_name AS type, COUNT(station.id_station) AS stations
FROM moyens_de_transport
JOIN station ON moyens_de_transport.id_mdt = station.moyen_de_transport_id
GROUP BY moyens_de_transport.line_name
ORDER BY stations DESC, moyens_de_transport.line_name;

CREATE VIEW view_line_duration AS
SELECT moyens_de_transport.line_name AS type, ligne.code AS line, moyens_de_transport.travel_time AS minutes
FROM moyens_de_transport
JOIN ligne ON moyens_de_transport.id_mdt = ligne.moyen_de_transport_id
ORDER BY moyens_de_transport.line_name, ligne.code;

CREATE VIEW view_station_capacity AS
SELECT station.station_name AS station, moyens_de_transport.max_capacity AS capacity
FROM station
JOIN moyens_de_transport ON station.moyen_de_transport_id = moyens_de_transport.id_mdt
WHERE LOWER(station.station_name) LIKE 'A%'
ORDER BY station.station_name, moyens_de_transport.max_capacity;

// procédures 

CREATE FUNCTION list_station_in_line(line_code VARCHAR(3))
RETURNS SETOF VARCHAR(64) AS $$
BEGIN
  RETURN QUERY
  SELECT station.station_name
  FROM station
  JOIN Ligne_Station ON station.id_station = Ligne_Station.station_id
  JOIN ligne ON Ligne_Station.ligne_id = ligne.id
  WHERE ligne.code = line_code
  ORDER BY Ligne_Station.position;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION list_types_in_zone(zone INT)
RETURNS SETOF VARCHAR(32) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT moyens_de_transport.line_name
  FROM moyens_de_transport
  JOIN station ON moyens_de_transport.id_mdt = station.moyen_de_transport_id
  WHERE station.zone_id = zone
  ORDER BY moyens_de_transport.line_name;
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