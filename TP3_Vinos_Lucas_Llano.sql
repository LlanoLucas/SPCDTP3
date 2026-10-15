-- TP3 - Base de datos de reseñas de vinos (WineEnthusiast)
-- Lucas Llano - 14/10/2026
-- MySQL 8.4

-- =============================================
-- 0. BASE DE DATOS
-- =============================================

-- as_ci: distingue acentos pero no mayúsculas
DROP DATABASE IF EXISTS vinos_tp3;
CREATE DATABASE vinos_tp3 CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_ci;
USE vinos_tp3;

SET NAMES utf8mb4 COLLATE utf8mb4_0900_as_ci;
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,ONLY_FULL_GROUP_BY';


-- =============================================
-- 1. CREACIÓN DE TABLAS
-- =============================================

CREATE TABLE pais (
    id_pais SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre VARCHAR(40) NOT NULL,
    CONSTRAINT pk_pais PRIMARY KEY (id_pais),
    CONSTRAINT uq_pais_nombre UNIQUE (nombre)
) ENGINE = InnoDB;

CREATE TABLE provincia (
    id_provincia SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre VARCHAR(50) NOT NULL,
    id_pais SMALLINT UNSIGNED NOT NULL,
    CONSTRAINT pk_provincia PRIMARY KEY (id_provincia),
    CONSTRAINT uq_provincia_nombre UNIQUE (id_pais, nombre),
    CONSTRAINT fk_provincia_pais FOREIGN KEY (id_pais) REFERENCES pais (id_pais)
) ENGINE = InnoDB;

-- region_1 del CSV
CREATE TABLE region (
    id_region SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre VARCHAR(60) NOT NULL,
    id_provincia SMALLINT UNSIGNED NOT NULL,
    CONSTRAINT pk_region PRIMARY KEY (id_region),
    CONSTRAINT uq_region_nombre UNIQUE (id_provincia, nombre),
    -- para la FK compuesta de vino
    CONSTRAINT uq_region_provincia UNIQUE (id_region, id_provincia),
    CONSTRAINT fk_region_provincia FOREIGN KEY (id_provincia) REFERENCES provincia (id_provincia)
) ENGINE = InnoDB;

-- region_2 del CSV (solo vinos de EE.UU.)
CREATE TABLE zona (
    id_zona TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre VARCHAR(30) NOT NULL,
    CONSTRAINT pk_zona PRIMARY KEY (id_zona),
    CONSTRAINT uq_zona_nombre UNIQUE (nombre)
) ENGINE = InnoDB;

CREATE TABLE bodega (
    id_bodega INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre VARCHAR(80) NOT NULL,
    CONSTRAINT pk_bodega PRIMARY KEY (id_bodega),
    CONSTRAINT uq_bodega_nombre UNIQUE (nombre)
) ENGINE = InnoDB;

CREATE TABLE variedad (
    id_variedad SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre VARCHAR(50) NOT NULL,
    CONSTRAINT pk_variedad PRIMARY KEY (id_variedad),
    CONSTRAINT uq_variedad_nombre UNIQUE (nombre)
) ENGINE = InnoDB;

-- usuario_twitter no es UNIQUE porque dos catadores comparten la cuenta
CREATE TABLE catador (
    id_catador TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre VARCHAR(40) NOT NULL,
    usuario_twitter VARCHAR(30) NULL,
    CONSTRAINT pk_catador PRIMARY KEY (id_catador),
    CONSTRAINT uq_catador_nombre UNIQUE (nombre),
    CONSTRAINT ck_catador_twitter CHECK (usuario_twitter IS NULL OR usuario_twitter LIKE '@%')
) ENGINE = InnoDB;

-- precio y puntos van en resena porque un mismo vino tiene precios distintos según la reseña
CREATE TABLE vino (
    id_vino INT UNSIGNED NOT NULL AUTO_INCREMENT,
    titulo VARCHAR(150) NOT NULL,
    designacion VARCHAR(100) NULL,
    anio_cosecha SMALLINT UNSIGNED NULL,
    id_bodega INT UNSIGNED NOT NULL,
    id_variedad SMALLINT UNSIGNED NULL,
    id_provincia SMALLINT UNSIGNED NULL,
    id_region SMALLINT UNSIGNED NULL,
    id_zona TINYINT UNSIGNED NULL,
    -- hash porque un UNIQUE común deja repetir filas cuando hay NULL
    clave_natural CHAR(32) AS (MD5(CONCAT_WS('|', LOWER(titulo), IFNULL(LOWER(designacion), '-'),
        id_bodega, IFNULL(id_variedad, 0), IFNULL(id_provincia, 0),
        IFNULL(id_region, 0), IFNULL(id_zona, 0)))) STORED,
    CONSTRAINT pk_vino PRIMARY KEY (id_vino),
    CONSTRAINT uq_vino_clave UNIQUE (clave_natural),
    CONSTRAINT ck_vino_anio CHECK (anio_cosecha BETWEEN 1900 AND 2017),
    CONSTRAINT ck_vino_region CHECK (id_region IS NULL OR id_provincia IS NOT NULL),
    CONSTRAINT fk_vino_bodega FOREIGN KEY (id_bodega) REFERENCES bodega (id_bodega),
    CONSTRAINT fk_vino_variedad FOREIGN KEY (id_variedad) REFERENCES variedad (id_variedad),
    CONSTRAINT fk_vino_provincia FOREIGN KEY (id_provincia) REFERENCES provincia (id_provincia),
    -- la región tiene que ser de la misma provincia del vino
    CONSTRAINT fk_vino_region FOREIGN KEY (id_region, id_provincia) REFERENCES region (id_region, id_provincia),
    CONSTRAINT fk_vino_zona FOREIGN KEY (id_zona) REFERENCES zona (id_zona),
    INDEX ix_vino_anio (anio_cosecha)
) ENGINE = InnoDB;

CREATE TABLE resena (
    id_resena INT UNSIGNED NOT NULL, -- índice del CSV original
    id_vino INT UNSIGNED NOT NULL,
    id_catador TINYINT UNSIGNED NULL,
    puntos TINYINT UNSIGNED NOT NULL,
    precio DECIMAL(7,2) NULL, -- en dólares
    descripcion TEXT NOT NULL,
    fecha_carga TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_resena PRIMARY KEY (id_resena),
    CONSTRAINT ck_resena_puntos CHECK (puntos BETWEEN 80 AND 100),
    CONSTRAINT ck_resena_precio CHECK (precio IS NULL OR precio > 0),
    CONSTRAINT fk_resena_vino FOREIGN KEY (id_vino) REFERENCES vino (id_vino),
    CONSTRAINT fk_resena_catador FOREIGN KEY (id_catador) REFERENCES catador (id_catador),
    INDEX ix_resena_puntos (puntos),
    INDEX ix_resena_precio (precio)
) ENGINE = InnoDB;


-- =============================================
-- 2. STAGING Y CARGA DEL CSV
-- =============================================

CREATE TABLE stg_resena (
    id_original INT UNSIGNED NOT NULL PRIMARY KEY,
    pais VARCHAR(40),
    descripcion TEXT,
    designacion VARCHAR(100),
    puntos TINYINT UNSIGNED,
    precio DECIMAL(7,2),
    provincia VARCHAR(50),
    region_1 VARCHAR(60),
    region_2 VARCHAR(30),
    catador VARCHAR(40),
    twitter VARCHAR(30),
    titulo VARCHAR(150),
    variedad VARCHAR(50),
    bodega VARCHAR(80),
    -- se completan en la carga
    hash_fila CHAR(32),
    es_duplicado BOOLEAN NOT NULL DEFAULT FALSE,
    id_pais SMALLINT UNSIGNED,
    id_provincia SMALLINT UNSIGNED,
    id_region SMALLINT UNSIGNED,
    id_zona TINYINT UNSIGNED,
    id_bodega INT UNSIGNED,
    id_variedad SMALLINT UNSIGNED,
    id_catador TINYINT UNSIGNED,
    clave_vino CHAR(32),
    INDEX ix_stg_hash (hash_fila),
    INDEX ix_stg_clave (clave_vino)
) ENGINE = InnoDB;

-- el CSV es el del documento extra, ya limpio (filas partidas y acentos arreglados, ver informe)
-- ESCAPED BY '' porque algunas descripciones tienen barras invertidas
LOAD DATA LOCAL INFILE 'datos/winemag_limpio.csv'
INTO TABLE stg_resena
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(id_original, @pais, @descripcion, @designacion, puntos, @precio, @provincia,
 @region_1, @region_2, @catador, @twitter, titulo, @variedad, bodega)
SET pais = NULLIF(@pais, ''),
    descripcion = @descripcion,
    designacion = NULLIF(@designacion, ''),
    precio = NULLIF(@precio, ''),
    provincia = NULLIF(@provincia, ''),
    region_1 = NULLIF(@region_1, ''),
    region_2 = NULLIF(@region_2, ''),
    catador = NULLIF(@catador, ''),
    twitter = NULLIF(@twitter, ''),
    variedad = NULLIF(@variedad, '');

-- tienen que ser 129971
SELECT COUNT(*) AS filas_cargadas_en_staging FROM stg_resena;


-- =============================================
-- 3. CARGA DE LAS TABLAS (con transacción)
-- =============================================

START TRANSACTION;

-- duplicados: filas iguales en todo menos el índice, se deja solo la primera
UPDATE stg_resena
SET hash_fila = MD5(CONCAT_WS('|', pais, descripcion, designacion, puntos, precio, provincia,
    region_1, region_2, catador, twitter, titulo, variedad, bodega));

UPDATE stg_resena s
JOIN (
    SELECT id_original,
           ROW_NUMBER() OVER (PARTITION BY hash_fila ORDER BY id_original) AS nro
    FROM stg_resena
) d ON d.id_original = s.id_original
SET s.es_duplicado = (d.nro > 1);

SELECT SUM(es_duplicado) AS duplicados_detectados,
       SUM(NOT es_duplicado) AS resenas_unicas
FROM stg_resena;

-- primero las tablas sin dependencias y la geografía de arriba hacia abajo (país > provincia > región)
INSERT INTO pais (nombre)
SELECT DISTINCT pais FROM stg_resena WHERE pais IS NOT NULL;

INSERT INTO provincia (nombre, id_pais)
SELECT DISTINCT s.provincia, p.id_pais
FROM stg_resena s
JOIN pais p ON p.nombre = s.pais
WHERE s.provincia IS NOT NULL;

INSERT INTO region (nombre, id_provincia)
SELECT DISTINCT s.region_1, pr.id_provincia
FROM stg_resena s
JOIN pais p ON p.nombre = s.pais
JOIN provincia pr ON pr.nombre = s.provincia AND pr.id_pais = p.id_pais
WHERE s.region_1 IS NOT NULL;

INSERT INTO zona (nombre)
SELECT DISTINCT region_2 FROM stg_resena WHERE region_2 IS NOT NULL;

INSERT INTO bodega (nombre)
SELECT DISTINCT bodega FROM stg_resena;

INSERT INTO variedad (nombre)
SELECT DISTINCT variedad FROM stg_resena WHERE variedad IS NOT NULL;

INSERT INTO catador (nombre, usuario_twitter)
SELECT catador, MAX(twitter)
FROM stg_resena
WHERE catador IS NOT NULL
GROUP BY catador;

-- le pongo a cada fila del staging los id de las tablas que ya cargué
-- LEFT JOIN para no perder las filas con datos faltantes
UPDATE stg_resena s
LEFT JOIN pais p ON p.nombre = s.pais
LEFT JOIN provincia pr ON pr.nombre = s.provincia AND pr.id_pais = p.id_pais
LEFT JOIN region r ON r.nombre = s.region_1 AND r.id_provincia = pr.id_provincia
LEFT JOIN zona z ON z.nombre = s.region_2
LEFT JOIN bodega b ON b.nombre = s.bodega
LEFT JOIN variedad v ON v.nombre = s.variedad
LEFT JOIN catador c ON c.nombre = s.catador
SET s.id_pais = p.id_pais,
    s.id_provincia = pr.id_provincia,
    s.id_region = r.id_region,
    s.id_zona = z.id_zona,
    s.id_bodega = b.id_bodega,
    s.id_variedad = v.id_variedad,
    s.id_catador = c.id_catador;

-- mismo cálculo que vino.clave_natural
UPDATE stg_resena
SET clave_vino = MD5(CONCAT_WS('|', LOWER(titulo), IFNULL(LOWER(designacion), '-'),
    id_bodega, IFNULL(id_variedad, 0), IFNULL(id_provincia, 0),
    IFNULL(id_region, 0), IFNULL(id_zona, 0)));

-- el año sale del título, los "NV" quedan en NULL
INSERT INTO vino (titulo, designacion, anio_cosecha, id_bodega, id_variedad,
                  id_provincia, id_region, id_zona)
SELECT MIN(titulo),
       MIN(designacion),
       CASE WHEN CAST(REGEXP_SUBSTR(MIN(titulo), '(19|20)[0-9]{2}') AS UNSIGNED) BETWEEN 1900 AND 2017
            THEN CAST(REGEXP_SUBSTR(MIN(titulo), '(19|20)[0-9]{2}') AS UNSIGNED)
       END,
       id_bodega, id_variedad, id_provincia, id_region, id_zona
FROM stg_resena
WHERE NOT es_duplicado
GROUP BY clave_vino, id_bodega, id_variedad, id_provincia, id_region, id_zona;

-- las reseñas sin duplicados, cada una con su vino
INSERT INTO resena (id_resena, id_vino, id_catador, puntos, precio, descripcion)
SELECT s.id_original, v.id_vino, s.id_catador, s.puntos, s.precio, s.descripcion
FROM stg_resena s
JOIN vino v ON v.clave_natural = s.clave_vino
WHERE NOT s.es_duplicado;

COMMIT;

-- sin esto la C06 tarda casi 3 minutos (mal plan por falta de estadísticas)
ANALYZE TABLE pais, provincia, region, zona, bodega, variedad, catador, vino, resena;

-- control: filas por tabla
SELECT 'pais' AS tabla, COUNT(*) AS filas FROM pais
UNION ALL SELECT 'provincia', COUNT(*) FROM provincia
UNION ALL SELECT 'region', COUNT(*) FROM region
UNION ALL SELECT 'zona', COUNT(*) FROM zona
UNION ALL SELECT 'bodega', COUNT(*) FROM bodega
UNION ALL SELECT 'variedad', COUNT(*) FROM variedad
UNION ALL SELECT 'catador', COUNT(*) FROM catador
UNION ALL SELECT 'vino', COUNT(*) FROM vino
UNION ALL SELECT 'resena', COUNT(*) FROM resena;

-- tiene que dar 0
SELECT COUNT(*) AS resenas_perdidas
FROM stg_resena s
WHERE NOT s.es_duplicado
  AND NOT EXISTS (SELECT 1 FROM resena r WHERE r.id_resena = s.id_original);


-- =============================================
-- 4. FUNCIONES, TRIGGER, PROCEDIMIENTO Y VISTA
-- =============================================

DELIMITER //

CREATE FUNCTION fn_rango_precio(p_precio DECIMAL(7,2))
RETURNS VARCHAR(20) DETERMINISTIC NO SQL
BEGIN
    RETURN CASE
        WHEN p_precio IS NULL THEN 'Sin precio'
        WHEN p_precio < 15 THEN '1. < 15'
        WHEN p_precio < 30 THEN '2. 15-29'
        WHEN p_precio < 60 THEN '3. 30-59'
        WHEN p_precio < 100 THEN '4. 60-99'
        ELSE '5. >= 100'
    END;
END //

-- escala de WineEnthusiast
CREATE FUNCTION fn_categoria_puntaje(p_puntos TINYINT UNSIGNED)
RETURNS VARCHAR(20) DETERMINISTIC NO SQL
BEGIN
    RETURN CASE
        WHEN p_puntos >= 98 THEN '6. Clásico'
        WHEN p_puntos >= 94 THEN '5. Soberbio'
        WHEN p_puntos >= 90 THEN '4. Excelente'
        WHEN p_puntos >= 87 THEN '3. Muy bueno'
        WHEN p_puntos >= 83 THEN '2. Bueno'
        ELSE '1. Aceptable'
    END;
END //

-- con un CHECK no se puede porque primero hay que hacer el TRIM
CREATE TRIGGER tg_resena_validar
BEFORE INSERT ON resena
FOR EACH ROW
BEGIN
    SET NEW.descripcion = TRIM(NEW.descripcion);
    IF CHAR_LENGTH(NEW.descripcion) < 10 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La descripción de la reseña es demasiado corta (mínimo 10 caracteres).';
    END IF;
END //

CREATE PROCEDURE sp_variedades_region(IN p_region VARCHAR(60), IN p_top INT)
BEGIN
    SELECT va.nombre AS variedad,
           COUNT(*) AS resenas,
           ROUND(AVG(r.puntos), 2) AS puntaje_promedio,
           ROUND(AVG(r.precio), 2) AS precio_promedio
    FROM resena r
    JOIN vino v ON v.id_vino = r.id_vino
    JOIN region rg ON rg.id_region = v.id_region
    JOIN variedad va ON va.id_variedad = v.id_variedad
    WHERE rg.nombre = p_region
    GROUP BY va.nombre
    ORDER BY resenas DESC
    LIMIT p_top;
END //

DELIMITER ;

CREATE VIEW v_hechos_resena AS
SELECT r.id_resena,
       r.puntos,
       r.precio,
       fn_rango_precio(r.precio) AS rango_precio,
       fn_categoria_puntaje(r.puntos) AS categoria,
       v.id_vino,
       v.titulo,
       v.anio_cosecha,
       pa.nombre AS pais,
       pr.nombre AS provincia,
       rg.nombre AS region,
       z.nombre AS zona,
       b.nombre AS bodega,
       va.nombre AS variedad,
       c.nombre AS catador
FROM resena r
JOIN vino v ON v.id_vino = r.id_vino
JOIN bodega b ON b.id_bodega = v.id_bodega
LEFT JOIN variedad va ON va.id_variedad = v.id_variedad
LEFT JOIN provincia pr ON pr.id_provincia = v.id_provincia
LEFT JOIN pais pa ON pa.id_pais = pr.id_pais
LEFT JOIN region rg ON rg.id_region = v.id_region
LEFT JOIN zona z ON z.id_zona = v.id_zona
LEFT JOIN catador c ON c.id_catador = r.id_catador;


-- =============================================
-- 5. PRUEBAS DE INTEGRIDAD Y TRANSACCIONES
-- =============================================
-- todos estos casos tienen que fallar. sp_probar ejecuta la sentencia y muestra el error en vez de cortar el script

DELIMITER //

CREATE PROCEDURE sp_probar(IN p_caso VARCHAR(80), IN p_sql TEXT)
BEGIN
    DECLARE v_msg TEXT DEFAULT 'ACEPTADO (no se esperaba)';
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    SET @sentencia = p_sql;
    PREPARE st FROM @sentencia;
    EXECUTE st;
    DEALLOCATE PREPARE st;
    SELECT p_caso AS prueba, v_msg AS respuesta_del_servidor;
END //

DELIMITER ;

SET @vino_ok = (SELECT MIN(id_vino) FROM vino);

CALL sp_probar('Puntaje fuera de escala (120)',
    CONCAT('INSERT INTO resena (id_resena, id_vino, puntos, descripcion) VALUES (900001, ', @vino_ok, ', 120, ''Prueba de puntaje inválido'')'));
CALL sp_probar('Precio negativo',
    CONCAT('INSERT INTO resena (id_resena, id_vino, puntos, precio, descripcion) VALUES (900002, ', @vino_ok, ', 90, -5, ''Prueba de precio inválido'')'));
CALL sp_probar('FK a un vino inexistente',
    'INSERT INTO resena (id_resena, id_vino, puntos, descripcion) VALUES (900003, 999999, 90, ''Prueba de clave foránea'')');
CALL sp_probar('Clave primaria repetida',
    'INSERT INTO resena (id_resena, id_vino, puntos, descripcion) SELECT id_resena, id_vino, puntos, descripcion FROM resena LIMIT 1');
CALL sp_probar('País duplicado (UNIQUE)',
    'INSERT INTO pais (nombre) VALUES (''Argentina'')');
CALL sp_probar('Borrar un país con vinos (RESTRICT)',
    'DELETE FROM pais WHERE nombre = ''Argentina''');
CALL sp_probar('Descripción vacía (trigger)',
    CONCAT('INSERT INTO resena (id_resena, id_vino, puntos, descripcion) VALUES (900004, ', @vino_ok, ', 90, ''   '')'));
-- provincia Mendoza con región Napa Valley
CALL sp_probar('Región de otra provincia (FK compuesta)',
    'INSERT INTO vino (titulo, id_bodega, id_provincia, id_region)
     SELECT ''Vino de prueba'', 1, (SELECT id_provincia FROM provincia WHERE nombre = ''Mendoza Province''),
            (SELECT id_region FROM region WHERE nombre = ''Napa Valley'')');

-- transacción que se deshace: el promedio tiene que terminar igual que al principio
SELECT ROUND(AVG(precio), 2) AS precio_medio_arg_antes
FROM v_hechos_resena WHERE pais = 'Argentina';

START TRANSACTION;

UPDATE resena r
JOIN vino v ON v.id_vino = r.id_vino
JOIN provincia p ON p.id_provincia = v.id_provincia
JOIN pais pa ON pa.id_pais = p.id_pais
SET r.precio = r.precio * 1.10
WHERE pa.nombre = 'Argentina' AND r.precio IS NOT NULL;

SELECT ROUND(AVG(precio), 2) AS precio_medio_arg_dentro_de_la_transaccion
FROM v_hechos_resena WHERE pais = 'Argentina';

SAVEPOINT antes_de_borrar;

DELETE r FROM resena r
JOIN catador c ON c.id_catador = r.id_catador
WHERE c.nombre = 'Michael Schachner' AND r.puntos < 82;

SELECT ROW_COUNT() AS resenas_borradas_temporalmente;

ROLLBACK TO SAVEPOINT antes_de_borrar; -- vuelve el borrado
ROLLBACK; -- descarta también el aumento

SELECT ROUND(AVG(precio), 2) AS precio_medio_arg_despues_del_rollback
FROM v_hechos_resena WHERE pais = 'Argentina';


-- =============================================
-- 6. CONSULTAS
-- =============================================

-- C01 - vinos y reseñas por país
SELECT pa.nombre AS pais,
       COUNT(DISTINCT v.id_vino) AS vinos,
       COUNT(*) AS resenas,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_resenas,
       ROUND(AVG(r.puntos), 2) AS puntaje_promedio
FROM resena r
JOIN vino v ON v.id_vino = r.id_vino
JOIN provincia p ON p.id_provincia = v.id_provincia
JOIN pais pa ON pa.id_pais = p.id_pais
GROUP BY pa.nombre
ORDER BY resenas DESC
LIMIT 15;

-- C02 - variedades más comunes en Mendoza
SELECT va.nombre AS variedad,
       COUNT(*) AS resenas,
       ROUND(AVG(r.puntos), 2) AS puntaje_promedio,
       ROUND(AVG(r.precio), 2) AS precio_promedio
FROM resena r
JOIN vino v ON v.id_vino = r.id_vino
JOIN provincia p ON p.id_provincia = v.id_provincia
JOIN variedad va ON va.id_variedad = v.id_variedad
WHERE p.nombre = 'Mendoza Province'
GROUP BY va.nombre
ORDER BY resenas DESC
LIMIT 10;

-- C03 - lo mismo para Napa Valley, con el procedimiento
CALL sp_variedades_region('Napa Valley', 8);

-- C04 - precio promedio por puntuación
SELECT r.puntos,
       COUNT(r.precio) AS resenas_con_precio,
       ROUND(AVG(r.precio), 2) AS precio_promedio,
       MIN(r.precio) AS precio_minimo,
       MAX(r.precio) AS precio_maximo
FROM resena r
GROUP BY r.puntos
ORDER BY r.puntos;

-- C05 - mejores bodegas (mínimo 30 reseñas)
SELECT b.nombre AS bodega,
       pa.nombre AS pais,
       COUNT(*) AS resenas,
       ROUND(AVG(r.puntos), 2) AS puntaje_promedio,
       ROUND(AVG(r.precio), 2) AS precio_promedio
FROM resena r
JOIN vino v ON v.id_vino = r.id_vino
JOIN bodega b ON b.id_bodega = v.id_bodega
JOIN provincia p ON p.id_provincia = v.id_provincia
JOIN pais pa ON pa.id_pais = p.id_pais
GROUP BY b.id_bodega, b.nombre, pa.nombre
HAVING COUNT(*) >= 30
ORDER BY puntaje_promedio DESC, resenas DESC
LIMIT 10;

-- C06 - vinos argentinos que cuestan más del triple del promedio de su provincia
SELECT v.titulo,
       p.nombre AS provincia,
       r.puntos,
       r.precio,
       ROUND((SELECT AVG(r2.precio)
              FROM resena r2 JOIN vino v2 ON v2.id_vino = r2.id_vino
              WHERE v2.id_provincia = v.id_provincia), 2) AS promedio_provincia
FROM resena r
JOIN vino v ON v.id_vino = r.id_vino
JOIN provincia p ON p.id_provincia = v.id_provincia
JOIN pais pa ON pa.id_pais = p.id_pais
WHERE pa.nombre = 'Argentina'
  AND r.precio > 3 * (SELECT AVG(r2.precio)
                      FROM resena r2 JOIN vino v2 ON v2.id_vino = r2.id_vino
                      WHERE v2.id_provincia = v.id_provincia)
ORDER BY r.precio DESC, r.id_resena DESC
LIMIT 10;

-- C07 - calidad/precio: 93 puntos o más por 20 dólares o menos
SELECT v.titulo,
       pa.nombre AS pais,
       va.nombre AS variedad,
       r.puntos,
       r.precio,
       ROUND(r.puntos / r.precio, 2) AS puntos_por_dolar
FROM resena r
JOIN vino v ON v.id_vino = r.id_vino
JOIN variedad va ON va.id_variedad = v.id_variedad
JOIN provincia p ON p.id_provincia = v.id_provincia
JOIN pais pa ON pa.id_pais = p.id_pais
WHERE r.puntos >= 93 AND r.precio <= 20
ORDER BY puntos_por_dolar DESC, r.puntos DESC, v.titulo
LIMIT 10;

-- C08 - perfil de los catadores
SELECT c.nombre AS catador,
       COUNT(*) AS resenas,
       ROUND(AVG(r.puntos), 2) AS puntaje_promedio,
       ROUND(STDDEV_SAMP(r.puntos), 2) AS desvio,
       ROUND(100 * AVG(CASE WHEN r.puntos >= 90 THEN 1 ELSE 0 END), 1) AS pct_90_o_mas,
       COUNT(DISTINCT p.id_pais) AS paises_cubiertos
FROM resena r
JOIN catador c ON c.id_catador = r.id_catador
JOIN vino v ON v.id_vino = r.id_vino
LEFT JOIN provincia p ON p.id_provincia = v.id_provincia
GROUP BY c.nombre
ORDER BY resenas DESC;

-- C09 - top 3 variedades de los 6 países con más reseñas
WITH top_paises AS (
    SELECT pais FROM v_hechos_resena
    WHERE pais IS NOT NULL
    GROUP BY pais
    ORDER BY COUNT(*) DESC
    LIMIT 6
),
ranking AS (
    SELECT h.pais,
           h.variedad,
           COUNT(*) AS resenas,
           ROW_NUMBER() OVER (PARTITION BY h.pais ORDER BY COUNT(*) DESC) AS puesto
    FROM v_hechos_resena h
    JOIN top_paises t ON t.pais = h.pais
    WHERE h.variedad IS NOT NULL
    GROUP BY h.pais, h.variedad
)
SELECT pais, puesto, variedad, resenas
FROM ranking
WHERE puesto <= 3
ORDER BY pais, puesto;

-- C10 - cuartiles de precio
WITH cuartiles AS (
    SELECT puntos, precio, NTILE(4) OVER (ORDER BY precio) AS cuartil
    FROM resena
    WHERE precio IS NOT NULL
)
SELECT cuartil,
       MIN(precio) AS desde,
       MAX(precio) AS hasta,
       COUNT(*) AS resenas,
       ROUND(AVG(puntos), 2) AS puntaje_promedio,
       ROUND(100 * AVG(puntos >= 90), 1) AS pct_90_o_mas
FROM cuartiles
GROUP BY cuartil
ORDER BY cuartil;

-- C11 - países con 50+ reseñas sin ningún vino de 95 o más
SELECT pa.nombre AS pais,
       (SELECT COUNT(*) FROM v_hechos_resena h WHERE h.pais = pa.nombre) AS resenas,
       (SELECT MAX(h.puntos) FROM v_hechos_resena h WHERE h.pais = pa.nombre) AS puntaje_maximo
FROM pais pa
WHERE NOT EXISTS (
        SELECT 1 FROM v_hechos_resena h
        WHERE h.pais = pa.nombre AND h.puntos >= 95)
  AND (SELECT COUNT(*) FROM v_hechos_resena h WHERE h.pais = pa.nombre) >= 50
ORDER BY resenas DESC;

-- C12 - evolución por año de cosecha
SELECT anio_cosecha,
       COUNT(*) AS resenas,
       ROUND(AVG(puntos), 2) AS puntaje_promedio,
       ROUND(AVG(precio), 2) AS precio_promedio,
       ROUND(AVG(puntos) - LAG(AVG(puntos)) OVER (ORDER BY anio_cosecha), 2) AS variacion_puntaje
FROM v_hechos_resena
WHERE anio_cosecha BETWEEN 2000 AND 2015
GROUP BY anio_cosecha
ORDER BY anio_cosecha;

-- C13 - variedades con más de 1000 reseñas y promedio arriba del general
SELECT va.nombre AS variedad,
       COUNT(*) AS resenas,
       ROUND(AVG(r.puntos), 2) AS puntaje_promedio,
       ROUND(AVG(r.precio), 2) AS precio_promedio
FROM resena r
JOIN vino v ON v.id_vino = r.id_vino
JOIN variedad va ON va.id_variedad = v.id_variedad
GROUP BY va.nombre
HAVING COUNT(*) > 1000
   AND AVG(r.puntos) > (SELECT AVG(puntos) FROM resena)
ORDER BY puntaje_promedio DESC;

-- C14 - mejor bodega de cada país (RANK para que salgan los empates)
SELECT pais, bodega, resenas, puntaje_promedio
FROM (
    SELECT pais,
           bodega,
           COUNT(*) AS resenas,
           ROUND(AVG(puntos), 2) AS puntaje_promedio,
           RANK() OVER (PARTITION BY pais ORDER BY AVG(puntos) DESC) AS puesto
    FROM v_hechos_resena
    WHERE pais IS NOT NULL
    GROUP BY pais, bodega
    HAVING COUNT(*) >= 10
) t
WHERE puesto = 1
ORDER BY puntaje_promedio DESC
LIMIT 12;


-- =============================================
-- 7. ANÁLISIS MULTIDIMENSIONAL
-- =============================================

-- M01 - roll-up país > rango de precio
SELECT IF(GROUPING(pais) = 1, '(TOTAL)', pais) AS pais,
       IF(GROUPING(rango_precio) = 1, '(subtotal)', rango_precio) AS rango_precio,
       COUNT(*) AS resenas,
       ROUND(AVG(puntos), 2) AS puntaje_promedio
FROM v_hechos_resena
WHERE pais IN ('Argentina', 'Chile', 'Spain')
GROUP BY pais, rango_precio WITH ROLLUP;

-- M02 - drill-down en Argentina: provincia > región
SELECT IF(GROUPING(provincia) = 1, '(total Argentina)', provincia) AS provincia,
       IF(GROUPING(region) = 1, '(subtotal)', IFNULL(region, '(sin región)')) AS region,
       COUNT(*) AS resenas,
       ROUND(AVG(puntos), 2) AS puntaje_promedio,
       ROUND(AVG(precio), 2) AS precio_promedio
FROM v_hechos_resena
WHERE pais = 'Argentina'
GROUP BY provincia, region WITH ROLLUP
HAVING COUNT(*) >= 20;

-- M03 - pivot país x categoría (% de cada país)
SELECT pais,
       COUNT(*) AS resenas,
       ROUND(100 * AVG(categoria = '1. Aceptable'), 1) AS pct_aceptable,
       ROUND(100 * AVG(categoria = '2. Bueno'), 1) AS pct_bueno,
       ROUND(100 * AVG(categoria = '3. Muy bueno'), 1) AS pct_muy_bueno,
       ROUND(100 * AVG(categoria = '4. Excelente'), 1) AS pct_excelente,
       ROUND(100 * AVG(categoria IN ('5. Soberbio', '6. Clásico')), 1) AS pct_soberbio_o_mas
FROM v_hechos_resena
WHERE pais IS NOT NULL
GROUP BY pais
HAVING COUNT(*) >= 1000
ORDER BY pct_excelente + pct_soberbio_o_mas DESC;

-- M04 - slice: solo Malbec, por país
SELECT pais,
       COUNT(*) AS resenas,
       ROUND(AVG(puntos), 2) AS puntaje_promedio,
       ROUND(AVG(precio), 2) AS precio_promedio,
       ROUND(AVG(puntos) / AVG(precio), 2) AS puntos_por_dolar
FROM v_hechos_resena
WHERE variedad = 'Malbec'
GROUP BY pais
HAVING COUNT(*) >= 20
ORDER BY resenas DESC;

-- M05 - dice: 3 países x 2 variedades x 2 rangos de precio
SELECT pais,
       variedad,
       rango_precio,
       COUNT(*) AS resenas,
       ROUND(AVG(puntos), 2) AS puntaje_promedio
FROM v_hechos_resena
WHERE pais IN ('Argentina', 'Chile', 'US')
  AND variedad IN ('Malbec', 'Cabernet Sauvignon')
  AND rango_precio IN ('2. 15-29', '3. 30-59')
GROUP BY pais, variedad, rango_precio
HAVING COUNT(*) >= 10
ORDER BY variedad, rango_precio, puntaje_promedio DESC;

-- M06 - cubo país x variedad (MySQL no tiene CUBE)
WITH base AS (
    SELECT pais, variedad, puntos
    FROM v_hechos_resena
    WHERE pais IN ('France', 'Italy', 'US')
      AND variedad IN ('Pinot Noir', 'Chardonnay', 'Red Blend')
)
SELECT pais, variedad, COUNT(*) AS resenas, ROUND(AVG(puntos), 2) AS puntaje_promedio
FROM base GROUP BY pais, variedad
UNION ALL
SELECT pais, '(todas)', COUNT(*), ROUND(AVG(puntos), 2)
FROM base GROUP BY pais
UNION ALL
SELECT '(todos)', variedad, COUNT(*), ROUND(AVG(puntos), 2)
FROM base GROUP BY variedad
UNION ALL
SELECT '(todos)', '(todas)', COUNT(*), ROUND(AVG(puntos), 2)
FROM base
ORDER BY pais, variedad;

-- M07 - puntaje promedio por país (top 10) y rango de precio
SELECT pais,
       ROUND(AVG(CASE WHEN rango_precio = '1. < 15' THEN puntos END), 2) AS menos_15,
       ROUND(AVG(CASE WHEN rango_precio = '2. 15-29' THEN puntos END), 2) AS de_15_a_29,
       ROUND(AVG(CASE WHEN rango_precio = '3. 30-59' THEN puntos END), 2) AS de_30_a_59,
       ROUND(AVG(CASE WHEN rango_precio = '4. 60-99' THEN puntos END), 2) AS de_60_a_99,
       ROUND(AVG(CASE WHEN rango_precio = '5. >= 100' THEN puntos END), 2) AS de_100_o_mas
FROM v_hechos_resena
WHERE pais IN (SELECT pais FROM (
                   SELECT pais FROM v_hechos_resena
                   WHERE pais IS NOT NULL
                   GROUP BY pais ORDER BY COUNT(*) DESC LIMIT 10) t)
GROUP BY pais
ORDER BY pais;
