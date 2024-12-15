// Niveau 1 - Requête SQL

// add_transport_type

CREATE FUNCTION add_transport_type( id_mdt char(3), line_name varchar(32), max_capacity integer, avg_travel_time integer )
RETURNS boolean AS $$
BEGIN
  INSERT INTO moyens_de_transport (id_mdt, name, max_capacity, travel_time)
  VALUES (id_mdt, line_name, max_capacity, travel_time);
END;
$$ LANGUAGE plpgsql;

// add_zone

CREATE FUNCTION add_zone(name varchar(32), price float)
RETURNS boolean AS $$
BEGIN
 IF price <= O THEN
    RAISE EXCEPTION 'Un prix ne peut être ni nul ni négatif';
END IF;

INSERT INTO zone (name, price)
VALUES (name, price);
END;
$$ LANGUAGE plpgsql;

// add_station

CREATE FUNCTION add_station(id_station integer, station_name varchar(64), station_commune varchar(64), zone_id integer, commune_id integer)
RETURNS boolean AS $$
BEGIN

IF NOT EXISTS (SELECT * FROM zone WHERE id = zone_id) THEN
    RAISE EXCEPTION 'La zone n''existe pas';
END IF;

IF NOT EXISTS (SELECT * FROM commune WHERE id = commune_id) THEN
    RAISE EXCEPTION 'La commune n''existe pas';
END IF;

INSERT INTO station (id_station, station_name, station_commune, zone_id, commune_id)
VALUES (id_station, station_name, station_commune, zone_id, commune_id);
END;
$$ LANGUAGE plpgsql;

// add_line

