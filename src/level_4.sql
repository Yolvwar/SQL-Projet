// Niveau 4

// Fonctions

CREATE FUNCTION add_journey(
  email VARCHAR(128),
  time_start TIMESTAMP,
  time_end TIMESTAMP,
  station_start INT,
  station_end INT
)
RETURNS BOOLEAN AS $$
BEGIN
  IF time_end - time_start > INTERVAL '24 hours' THEN
    RAISE EXCEPTION 'Le voyage ne peut faire plus de 24 heures';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM journey
    WHERE user_id = (SELECT id FROM user WHERE email = email)
      AND (entry_time, exit_time) OVERLAPS (time_start, time_end)
  ) THEN
    RAISE EXCEPTION 'Le voyageur ne peut avoir plus d''un trajet au même moment';
  END IF;

  INSERT INTO journey (user_id, entry_time, exit_time, entry_station_id, exit_station_id)
  VALUES (
    (SELECT id FROM user WHERE email = email),
    time_start,
    time_end,
    station_start,
    station_end
  );

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION add_bill(
  email VARCHAR(128),
  year INT,
  month INT
)
RETURNS BOOLEAN AS $$
DECLARE
  user_id INT;
  total_amount FLOAT := 0;
  reduction_percentage INT := 0;
  subscription_id INT;
BEGIN
  SELECT id INTO user_id FROM user WHERE email = email;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L''utilisateur spécifié n''existe pas';
  END IF;

  IF (year, month) >= (EXTRACT(YEAR FROM CURRENT_DATE), EXTRACT(MONTH FROM CURRENT_DATE)) THEN
    RAISE EXCEPTION 'Le mois doit être terminé';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM bill
    WHERE user_id = user_id
      AND EXTRACT(YEAR FROM date_bill) = year
      AND EXTRACT(MONTH FROM date_bill) = month
  ) THEN
    RAISE EXCEPTION 'Une facture pour ce mois et cette année existe déjà pour cet utilisateur';
  END IF;

  SELECT COALESCE(SUM(zone.zone_price), 0) INTO total_amount
  FROM journey
  JOIN station AS entry_station ON journey.entry_station_id = entry_station.id_station
  JOIN station AS exit_station ON journey.exit_station_id = exit_station.id_station
  JOIN zone ON entry_station.zone_id = zone.zone_number OR exit_station.zone_id = zone.zone_number
  WHERE journey.user_id = user_id
    AND EXTRACT(YEAR FROM journey.entry_time) = year
    AND EXTRACT(MONTH FROM journey.entry_time) = month;

  SELECT COALESCE(SUM(package.price_per_month), 0), subscription.id INTO total_amount, subscription_id
  FROM subscription
  JOIN package ON subscription.package_code = package.code
  WHERE subscription.users_id = user_id
    AND subscription.date_sub <= DATE_TRUNC('month', DATE 'year-month-01') + INTERVAL '1 month' - INTERVAL '1 day'
    AND (subscription.date_sub + INTERVAL '1 month' * package.duration_month) >= DATE_TRUNC('month', DATE 'year-month-01')
  GROUP BY subscription.id;

  SELECT COALESCE(service.reduction_percentage, 0) INTO reduction_percentage
  FROM employee
  JOIN contract ON employee.id = contract.employee_id
  JOIN service ON contract.service_id = service.id
  WHERE employee.user_id = user_id
    AND contract.employed_at <= DATE_TRUNC('month', DATE 'year-month-01') + INTERVAL '1 month' - INTERVAL '1 day'
    AND (contract.leaved_at IS NULL OR contract.leaved_at >= DATE_TRUNC('month', DATE 'year-month-01'));

  total_amount := total_amount * (1 - reduction_percentage / 100.0);
  total_amount := ROUND(total_amount, 2);

  IF total_amount = 0 THEN
    RETURN TRUE;
  END IF;

  INSERT INTO bill (user_id, subscription_id, total_price)
  VALUES (user_id, subscription_id, total_amount);

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pay_bill(
  email VARCHAR(128),
  year INT,
  month INT
)
RETURNS BOOLEAN AS $$
DECLARE
  user_id INT;
  bill_id INT;
  total_amount FLOAT;
BEGIN
  SELECT id INTO user_id FROM user WHERE email = email;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L''utilisateur spécifié n''existe pas';
  END IF;

  SELECT id, total_price INTO bill_id, total_amount
  FROM bill
  WHERE user_id = user_id
    AND EXTRACT(YEAR FROM date_bill) = year
    AND EXTRACT(MONTH FROM date_bill) = month;

  IF NOT FOUND THEN
    PERFORM add_bill(email, year, month);
    SELECT id, total_price INTO bill_id, total_amount
    FROM bill
    WHERE user_id = user_id
      AND EXTRACT(YEAR FROM date_bill) = year
      AND EXTRACT(MONTH FROM date_bill) = month;
  END IF;

  IF total_amount = 0 THEN
    RETURN FALSE;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM payment
    WHERE bill_id = bill_id
  ) THEN
    RETURN TRUE;
  END IF;

  INSERT INTO payment (bill_id, date_payment)
  VALUES (bill_id, CURRENT_DATE);

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// views

CREATE OR REPLACE VIEW view_all_bills AS
SELECT 
  utilisateur.lastname,
  utilisateur.firstname,
  facture.id AS bill_number,
  facture.total_price AS bill_amount
FROM 
  utilisateur
JOIN 
  facture ON utilisateur.id = facture.utilisateur_id
ORDER BY 
  facture.id;

CREATE OR REPLACE VIEW view_bill_per_month AS
SELECT 
  EXTRACT(YEAR FROM date_facture) AS year,
  EXTRACT(MONTH FROM date_facture) AS month,
  COUNT(id) AS bills,
  SUM(total_price) AS total
FROM 
  facture
GROUP BY 
  EXTRACT(YEAR FROM date_facture), EXTRACT(MONTH FROM date_facture)
ORDER BY 
  year, month;

CREATE OR REPLACE VIEW view_average_entries_station AS
SELECT 
  transportation_means.line_name AS type,
  station.station_name AS station,
  ROUND(CAST(COUNT(trajet.entry_station_id) AS NUMERIC) / COUNT(DISTINCT DATE(trajet.entry_time)), 2) AS entries
FROM 
  trajet
JOIN 
  station ON trajet.entry_station_id = station.id_station
JOIN 
  transportation_means ON station.transportation_mode_id = transportation_means.id_mdt
GROUP BY 
  transportation_means.line_name, station.station_name
HAVING 
  COUNT(trajet.entry_station_id) > 0
ORDER BY 
  transportation_means.line_name, station.station_name;

CREATE OR REPLACE VIEW view_current_non_paid_bills AS
SELECT 
  utilisateur.lastname,
  utilisateur.firstname,
  facture.id AS bill_number,
  facture.total_price AS bill_amount
FROM 
  utilisateur
JOIN 
  facture ON utilisateur.id = facture.utilisateur_id
LEFT JOIN 
  paiement ON facture.id = paiement.facture_id
WHERE 
  paiement.facture_id IS NULL
ORDER BY 
  utilisateur.lastname, utilisateur.firstname, facture.id;