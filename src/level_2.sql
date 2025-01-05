// Niveau 2 

CREATE OR REPLACE FUNCTION add_person(
    firstname VARCHAR(32),
    lastname VARCHAR(32),
    email VARCHAR(128),
    phone VARCHAR(10),
    address TEXT,
    town VARCHAR(32),
    zipcode VARCHAR(5)
) RETURNS BOOLEAN AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM utilisateur WHERE email = email) THEN
        RETURN FALSE;
    END IF;
    INSERT INTO utilisateur (firstname, lastname, email, phone_number, address, zipcode, commune_id)
    VALUES (firstname, lastname, email, phone, address, zipcode, 
            (SELECT id FROM commune WHERE commune_name = town));
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION add_offer(
  code VARCHAR(5),
  name VARCHAR(32),
  price FLOAT,
  nb_month INT,
  zone_from INT,
  zone_to INT
)
RETURNS BOOLEAN AS $$
BEGIN

  IF nb_month <= 0 THEN
    RAISE EXCEPTION 'Le nombre de mois doit être positif et non nul';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM zone WHERE zone_number = zone_from) OR
     NOT EXISTS (SELECT 1 FROM zone WHERE zone_number = zone_to) THEN
    RAISE EXCEPTION 'Les zones n''existent pas';
  END IF;

  INSERT INTO forfait (code, name, price_per_month, duration_month, min_zone, max_zone)
  VALUES (code, name, price, nb_month, zone_from, zone_to);

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION add_subscription(
  num INT,
  email VARCHAR(128),
  code VARCHAR(5),
  date_sub DATE
)
RETURNS BOOLEAN AS $$
BEGIN

  IF NOT EXISTS (SELECT 1 FROM utilisateur WHERE email = email) OR
     NOT EXISTS (SELECT 1 FROM forfait WHERE code = code) THEN
    RAISE EXCEPTION 'Utilisateur ou forfait n''existe pas';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM abonnement
    WHERE utilisateur_email = email
      AND status IN ('Pending', 'Incomplete')
  ) THEN
    RAISE EXCEPTION 'L''utilisateur a déja un abonnement en attente ou incomplet';
  END IF;

  INSERT INTO abonnement (num, utilisateur_email, forfait_code, date_sub, status)
  VALUES (num, email, code, date_sub, 'Incomplete');

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// Fonctions de MAJ

CREATE FUNCTION update_status(num INT, new_status VARCHAR(32))
RETURNS BOOLEAN AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM abonnement WHERE id = num) THEN
    RAISE EXCEPTION 'L''abonnement n''existe pas';
  END IF;

  IF new_status NOT IN ('Registered', 'Pending', 'Incomplete') THEN
    RAISE EXCEPTION 'Statut non valide';
  END IF;

  IF (SELECT statut FROM abonnement WHERE id = num) = new_status THEN
    RETURN TRUE;
  END IF;

  UPDATE abonnement
  SET statut = new_status
  WHERE id = num;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION update_offer_price(offer_code VARCHAR(5), price FLOAT)
RETURNS BOOLEAN AS $$
BEGIN
  IF price <= 0 THEN
    RAISE EXCEPTION 'Le prix doit être positif et non nul';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM forfait WHERE code = offer_code) THEN
    RAISE EXCEPTION 'Le forfait n''existe pas';
  END IF;

  UPDATE forfait
  SET price_per_month = price
  WHERE code = offer_code;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// views

CREATE OR REPLACE VIEW view_user_small_name AS
SELECT lastname, firstname
FROM utilisateur
WHERE LENGTH(lastname) <= 4
ORDER BY lastname, firstname;

CREATE OR REPLACE VIEW view_user_subscription AS
SELECT CONCAT(utilisateur.lastname, ' ', utilisateur.firstname) AS user,
       forfait.name AS offer
FROM utilisateur
JOIN abonnement ON utilisateur.email = abonnement.utilisateur_email
JOIN forfait ON abonnement.forfait_code = forfait.code
ORDER BY user, offer;

CREATE OR REPLACE VIEW view_unloved_offers AS
SELECT forfait.name AS offer
FROM forfait
LEFT JOIN abonnement ON forfait.code = abonnement.forfait_code
WHERE abonnement.forfait_code IS NULL
ORDER BY forfait.name;

CREATE OR REPLACE VIEW view_pending_subscriptions AS
SELECT utilisateur.lastname, utilisateur.firstname, abonnement.date_sub
FROM utilisateur
JOIN abonnement ON utilisateur.email = abonnement.utilisateur_email
WHERE abonnement.status = 'Pending'
ORDER BY abonnement.date_sub;

CREATE OR REPLACE VIEW view_old_subscription AS
SELECT utilisateur.lastname, utilisateur.firstname, forfait.name AS subscription, abonnement.status
FROM utilisateur
JOIN abonnement ON utilisateur.email = abonnement.utilisateur_email
JOIN forfait ON abonnement.forfait_code = forfait.code
WHERE abonnement.status IN ('Incomplete', 'Pending')
  AND abonnement.date_sub <= NOW() - INTERVAL '1 year'
ORDER BY utilisateur.lastname, utilisateur.firstname, forfait.name;