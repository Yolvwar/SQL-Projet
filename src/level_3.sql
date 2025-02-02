// Niveau 3

CREATE FUNCTION add_service(name VARCHAR(32), discount INT)
RETURNS BOOLEAN AS $$
BEGIN
  IF discount < 0 OR discount > 100 THEN
    RAISE EXCEPTION 'Pourcentage de réduction invalide, il doit être compris entre 0 et 100';
  END IF;

  IF EXISTS (SELECT 1 FROM service WHERE name = name) THEN
    RAISE EXCEPTION 'Le nom du service doit être unique';
  END IF;

  INSERT INTO service (name, reduction_percentage)
  VALUES (name, discount);

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION add_contract(login VARCHAR(20), email VARCHAR(128), date_beginning DATE, service VARCHAR(32)
)
RETURNS BOOLEAN AS $$
BEGIN

  IF NOT EXISTS (SELECT 1 FROM user WHERE email = email) THEN
    RAISE EXCEPTION 'L''user n''existe pas';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM service WHERE name = service) THEN
    RAISE EXCEPTION 'Le service n''existe pas';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM contract
    WHERE user_id = (SELECT id FROM user WHERE email = email)
      AND leaved_at IS NULL AND employeed_at < date_beginning
  ) THEN
    RAISE EXCEPTION 'Il faut que les contracts précédents soit fini avant de pouvoir en ajouter un nouveau';
  END IF;

  INSERT INTO employee (login, user_id)
  VALUES (login, SELECT id FROM user WHERE email = email);

  INSERT INTO contract (employee_id, employeed_at, service_id)
  VALUES (
    (SELECT id FROM employee WHERE login = login),
    date_beginning,
    (SELECT id FROM service WHERE name = service)
  );

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION end_contract(email VARCHAR(128), date_end DATE)
RETURNS BOOLEAN AS $$
BEGIN

  IF NOT EXISTS (SELECT 1 FROM user WHERE email = email) THEN
    RAISE EXCEPTION 'L''user n''existe pas';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM contract
    WHERE user_id = (SELECT id FROM user WHERE email = email) AND leaved_at IS NULL
  ) THEN
    RAISE EXCEPTION 'L''user n''a pas de contract';
  END IF;

  UPDATE contract
  SET leaved_at = date_end
  WHERE user_id = (SELECT id FROM user WHERE email = email) AND leaved_at IS NULL;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION update_service(name VARCHAR(32), discount INT)
RETURNS BOOLEAN AS $$
BEGIN

  IF discount < 0 OR discount > 100 THEN
    RAISE EXCEPTION 'Pourcentage de réduction invalide, il doit être compris entre 0 et 100';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM service WHERE name = name) THEN
    RAISE EXCEPTION 'Le service n''existe pas';
  END IF;

  UPDATE service
  SET reduction_percentage = discount
  WHERE name = name;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION update_employee_email(login VARCHAR(20), email VARCHAR(128))
RETURNS BOOLEAN AS $$
BEGIN

  IF NOT EXISTS (SELECT 1 FROM employee WHERE login = login) THEN
    RAISE EXCEPTION 'Le login n''existe pas';
  END IF;

  IF EXISTS (SELECT 1 FROM user WHERE email = email) THEN
    RAISE EXCEPTION 'L''adresse e-mail est dejà utilisé par un autre user';
  END IF;

  IF (SELECT email FROM user WHERE id = (SELECT user_id FROM employee WHERE login = login)) = email THEN
    RETURN TRUE;
  END IF;

  UPDATE user
  SET email = email
  WHERE id = SELECT user_id FROM employee WHERE login = login;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

// Vues 

CREATE OR REPLACE VIEW view_employees AS
SELECT employee.login, service.name, user.lastname, user.firstname AS service
FROM user
JOIN employee ON user.id = employee.user_id
JOIN contract ON employee.id = contract.employee_id
JOIN service ON contract.service_id = service.id
WHERE contract.leaved_at IS NULL
ORDER BY user.lastname, user.firstname, employee.login;

CREATE OR REPLACE VIEW view_nb_employees_per_service AS
SELECT service.name AS service, COUNT(employee.id) AS nb
FROM service
LEFT JOIN contract ON service.id = contract.service_id AND contract.leaved_at IS NULL
LEFT JOIN employee ON contract.employee_id = employee.id
GROUP BY service.name
ORDER BY service.name;

// procédures

CREATE FUNCTION list_login_employee(date_service DATE)
RETURNS SETOF VARCHAR(20) AS $$
BEGIN
  RETURN QUERY
  SELECT employee.login
  FROM employee
  JOIN contract ON employee.id = contract.employee_id
  WHERE contract.employeed_at <= date_service AND (contract.leaved_at IS NULL OR contract.leaved_at >= date_service)
  ORDER BY employee.login;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION list_not_employee(date_service DATE)
RETURNS TABLE(
  lastname VARCHAR(32),
  firstname VARCHAR(32),
  has_worked TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT user.lastname, user.firstname,
         CASE
           WHEN EXISTS (
             SELECT 1
             FROM contract
             WHERE contract.user_id = user.id
           ) THEN 'YES'
           ELSE 'NO'
         END AS has_worked
  FROM user
  WHERE NOT EXISTS (
    SELECT 1
    FROM employee
    JOIN contract ON employee.id = contract.employee_id
    WHERE employee.user_id = user.id
      AND contract.employeed_at <= date_service
      AND (contract.leaved_at IS NULL OR contract.leaved_at >= date_service)
  )
  ORDER BY user.lastname, user.firstname;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION list_subscription_history(email VARCHAR(128))
RETURNS TABLE(
  type TEXT,
  name VARCHAR,
  start_date DATE,
  duration INTERVAL
) AS $$
BEGIN
  RETURN QUERY
  SELECT 'sub' AS type,
         package.name AS name,
         subscription.date_sub AS start_date,
         (subscription.date_sub + INTERVAL '1 month' * package.duration_month) - subscription.date_sub AS duration
  FROM subscription
  JOIN package ON subscription.package_code = package.code
  WHERE subscription.user_email = email

  UNION ALL

  SELECT 'ctr' AS type,
         service.name AS name,
         contract.employeed_at AS start_date,
         CASE
           WHEN contract.leaved_at IS NOT NULL THEN
             contract.leaved_at - contract.employeed_at
           ELSE
             NULL
         END AS duration
  FROM contract
  JOIN employee ON contract.employee_id = employee.id
  JOIN service ON contract.service_id = service.id
  WHERE employee.user_id = (SELECT id FROM user WHERE email = email)
  ORDER BY start_date;
END;
$$ LANGUAGE plpgsql;