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
    IF EXISTS (SELECT 1 FROM user WHERE email = email) THEN
        RETURN FALSE;
    END IF;
    INSERT INTO user (firstname, lastname, email, phone_number, address, zipcode, municipality_id)
    VALUES (firstname, lastname, email, phone, address, zipcode, 
            (SELECT id FROM municipality WHERE municipality_name = town));
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

  INSERT INTO package (code, name, price_per_month, duration_month, min_zone, max_zone)
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

  IF NOT EXISTS (SELECT 1 FROM user WHERE email = email) OR
     NOT EXISTS (SELECT 1 FROM package WHERE code = code) THEN
    RAISE EXCEPTION 'user ou package n''existe pas';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM subscription
    WHERE user_email = email
      AND status IN ('Pending', 'Incomplete')
  ) THEN
    RAISE EXCEPTION 'L''user a déja un subscription en attente ou incomplet';
  END IF;

  INSERT INTO subscription (num, user_email, package_code, date_sub, status)
  VALUES (num, email, code, date_sub, 'Incomplete');

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// Fonctions de MAJ

CREATE FUNCTION update_status(num INT, new_status VARCHAR(32))
RETURNS BOOLEAN AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM subscription WHERE id = num) THEN
    RAISE EXCEPTION 'L''subscription n''existe pas';
  END IF;

  IF new_status NOT IN ('Registered', 'Pending', 'Incomplete') THEN
    RAISE EXCEPTION 'status non valide';
  END IF;

  IF (SELECT status FROM subscription WHERE id = num) = new_status THEN
    RETURN TRUE;
  END IF;

  UPDATE subscription
  SET status = new_status
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

  IF NOT EXISTS (SELECT 1 FROM package WHERE code = offer_code) THEN
    RAISE EXCEPTION 'Le package n''existe pas';
  END IF;

  UPDATE package
  SET price_per_month = price
  WHERE code = offer_code;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// views

CREATE OR REPLACE VIEW view_user_small_name AS
SELECT lastname, firstname
FROM user
WHERE LENGTH(lastname) <= 4
ORDER BY lastname, firstname;

CREATE OR REPLACE VIEW view_user_subscription AS
SELECT CONCAT(user.lastname, ' ', user.firstname) AS user,
       package.name AS offer
FROM user
JOIN subscription ON user.email = subscription.user_email
JOIN package ON subscription.package_code = package.code
ORDER BY user, offer;

CREATE OR REPLACE VIEW view_unloved_offers AS
SELECT package.name AS offer
FROM package
LEFT JOIN subscription ON package.code = subscription.package_code
WHERE subscription.package_code IS NULL
ORDER BY package.name;

CREATE OR REPLACE VIEW view_pending_subscriptions AS
SELECT user.lastname, user.firstname, subscription.date_sub
FROM user
JOIN subscription ON user.email = subscription.user_email
WHERE subscription.status = 'Pending'
ORDER BY subscription.date_sub;

CREATE OR REPLACE VIEW view_old_subscription AS
SELECT user.lastname, user.firstname, package.name AS subscription, subscription.status
FROM user
JOIN subscription ON user.email = subscription.user_email
JOIN package ON subscription.package_code = package.code
WHERE subscription.status IN ('Incomplete', 'Pending')
  AND subscription.date_sub <= NOW() - INTERVAL '1 year'
ORDER BY user.lastname, user.firstname, package.name;