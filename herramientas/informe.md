# 1. Introducción

## 1.1 Objetivo del trabajo

En este trabajo se construyó una base de datos relacional a partir del conjunto de reseñas de vinos publicado por la revista WineEnthusiast (archivo winemag-data-130k-v2.csv). El dataset original es una tabla plana de casi 130.000 filas en la que cada reseña repite el país, la provincia, la bodega, la variedad y el catador. Para una planilla eso alcanza, pero con esa estructura no hay forma de garantizar que los datos sean consistentes, y cada consulta tiene que recorrer texto repetido.

El trabajo se organizó en cuatro etapas, que coinciden con la consigna. Primero se diseñó un modelo relacional normalizado. Después se lo implementó en MySQL con restricciones de integridad y una carga transaccional. Sobre esa base se escribieron consultas SQL de complejidad creciente y, por último, se hizo un análisis multidimensional que cruza país, variedad, precio y puntaje.

## 1.2 Herramientas utilizadas

El SGBD elegido fue MySQL 8.4.9 Community Server, porque es el que pide el formato de entrega y porque desde la versión 8 incluye funciones de ventana, expresiones de tabla comunes (CTE), restricciones CHECK que realmente se validan y GROUP BY WITH ROLLUP con la función GROUPING(). Todo el código está en el archivo TP3_Vinos_Lucas_Llano.sql, que crea la base desde cero y se ejecuta de una sola vez con el cliente mysql.

Para extraer los datos del archivo Excel se escribió un script corto en Python, y con Python también se hicieron los gráficos.

# 2. Datos de origen y preparación

## 2.1 Estructura del archivo recibido

El archivo "Entregable 3 - Documentación extra.xlsm" no es una planilla con columnas: tiene una única columna en la que cada celda contiene una línea completa del CSV original, con las comas y las comillas incluidas. El encabezado tiene catorce campos: un índice sin nombre, country, description, designation, points, price, province, region_1, region_2, taster_name, taster_twitter_handle, title, variety y winery.

Al revisar el contenido aparecieron dos problemas. El primero es que unas 430 filas estaban partidas en dos o más columnas. La causa es que el CSV se abrió con el punto y coma como separador, de modo que cada descripción que tenía un ";" quedó cortada en ese punto. El segundo es un problema de codificación: el texto UTF-8 se interpretó como Windows-1252, por eso "Vulkà Bianco" aparecía como "VulkÃ  Bianco" y el apellido de la catadora Kerin O'Keefe como "Oâ€™Keefe".

## 2.2 Extracción y corrección de la codificación

El script herramientas/limpiar_datos.py resuelve ambos problemas antes de que los datos lleguen a MySQL. Lee el archivo .xlsm como lo que es, un ZIP con documentos XML, recorre la hoja fila por fila y vuelve a unir con ";" las celdas que se habían separado. Luego revierte la codificación (convierte cada carácter al byte que tenía en Windows-1252 y decodifica el resultado como UTF-8), parsea la línea con el módulo csv y escribe datos/winemag_limpio.csv.

La conversión directa fallaba en algunas palabras, como "Águila", y en las comillas tipográficas de cierre. El motivo es que Windows-1252 no define cinco posiciones (0x81, 0x8D, 0x8F, 0x90 y 0x9D) y Excel las había guardado como caracteres de control, así que el script trata esos caracteres aparte, como bytes crudos. El resultado final tiene 129.971 reseñas, la misma cantidad que el dataset original, y todas con catorce campos. Quedan seis valores con caracteres que parecen errores de codificación, pero cuatro son palabras francesas correctas ("Âge", "Âme") y los otros dos ("crÃ¨me anglaise") ya venían así en la fuente.

## 2.3 Perfil de los datos

Antes de diseñar el modelo convenía saber qué tan completos estaban los datos. La siguiente consulta, ejecutada sobre la tabla de staging que se describe en el capítulo 4, cuenta los valores ausentes de cada columna en el archivo tal como se recibió.

```ejecutar
SELECT 'country' AS columna, SUM(pais IS NULL) AS nulos, ROUND(100 * AVG(pais IS NULL), 2) AS pct FROM stg_resena
UNION ALL SELECT 'designation', SUM(designacion IS NULL), ROUND(100 * AVG(designacion IS NULL), 2) FROM stg_resena
UNION ALL SELECT 'price', SUM(precio IS NULL), ROUND(100 * AVG(precio IS NULL), 2) FROM stg_resena
UNION ALL SELECT 'province', SUM(provincia IS NULL), ROUND(100 * AVG(provincia IS NULL), 2) FROM stg_resena
UNION ALL SELECT 'region_1', SUM(region_1 IS NULL), ROUND(100 * AVG(region_1 IS NULL), 2) FROM stg_resena
UNION ALL SELECT 'region_2', SUM(region_2 IS NULL), ROUND(100 * AVG(region_2 IS NULL), 2) FROM stg_resena
UNION ALL SELECT 'taster_name', SUM(catador IS NULL), ROUND(100 * AVG(catador IS NULL), 2) FROM stg_resena
UNION ALL SELECT 'taster_twitter_handle', SUM(twitter IS NULL), ROUND(100 * AVG(twitter IS NULL), 2) FROM stg_resena
UNION ALL SELECT 'variety', SUM(variedad IS NULL), ROUND(100 * AVG(variedad IS NULL), 2) FROM stg_resena
```

::nota Tabla 1. Valores ausentes por columna en las 129.971 filas originales. Las columnas que no figuran están siempre completas.

La columna region_2 falta en el 61% de las filas porque WineEnthusiast solo la usa para vinos de Estados Unidos. El precio falta en el 6,9% de las reseñas, así que los promedios de precio tienen que ignorar esos casos en lugar de contarlos como cero. Además, una de cada cinco reseñas no tiene catador, por lo que esa relación tiene que ser opcional en el modelo.

El perfil también mostró 9.983 filas duplicadas: reseñas idénticas en todos sus campos que solo difieren en el índice. Si se las dejara, inflarían cada conteo y cada promedio. Su eliminación se hace en SQL durante la carga (sección 4.3).

# 3. Modelo relacional

## 3.1 Del archivo plano a las entidades

El punto de partida fue identificar las dependencias funcionales del archivo plano. Una provincia determina su país, una región (region_1) determina su provincia y un catador determina su usuario de Twitter. Estas dependencias transitivas son las que generan la repetición del CSV, y separarlas en tablas propias lleva el modelo a la tercera forma normal.

Más difícil fue decidir qué es un "vino". Una primera idea era tomar el título de la reseña como identificador, ya que incluye la bodega, la cosecha y la designación. Sin embargo, al agrupar por título aparecieron 578 vinos con precios distintos según la reseña y 751 con puntajes distintos. El precio y los puntos no dependen entonces del vino sino de cada evaluación, y por eso quedaron en la tabla resena. El vino se define como una etiqueta concreta: título, designación, bodega, variedad y origen.

Con ese criterio el modelo quedó en nueve tablas. Las tablas pais, provincia y region forman una jerarquía geográfica, y zona guarda las agrupaciones amplias de region_2. Las tablas bodega, variedad y catador funcionan como catálogos. Por último, vino representa la etiqueta y resena la evaluación; esta última es además la tabla de hechos del análisis del capítulo 6.

## 3.2 Esquema de las tablas

La tabla siguiente resume cada entidad. El detalle completo de tipos y restricciones está en la sección 1 del script SQL y en el diagrama de la sección 3.5.

| Tabla | Clave primaria | Claves foráneas | Otras restricciones | Filas |
| pais | id_pais | | nombre UNIQUE | 43 |
| provincia | id_provincia | id_pais → pais | UNIQUE (id_pais, nombre) | 425 |
| region | id_region | id_provincia → provincia | UNIQUE (id_provincia, nombre); UNIQUE (id_region, id_provincia) | 1.231 |
| zona | id_zona | | nombre UNIQUE | 17 |
| bodega | id_bodega | | nombre UNIQUE | 16.728 |
| variedad | id_variedad | | nombre UNIQUE | 707 |
| catador | id_catador | | nombre UNIQUE; CHECK usuario_twitter LIKE '@%' | 19 |
| vino | id_vino | id_bodega, id_variedad, id_provincia, (id_region, id_provincia), id_zona | clave_natural UNIQUE; CHECK anio_cosecha 1900-2017 | 119.082 |
| resena | id_resena | id_vino → vino; id_catador → catador | CHECK puntos 80-100; CHECK precio > 0; trigger de validación | 119.988 |

::nota Tabla 2. Resumen del esquema con la cantidad de filas cargadas.

Cada tabla tiene solo los atributos que necesita. En pais, zona, bodega y variedad hay un identificador y un nombre, y en catador se agrega usuario_twitter. La tabla vino guarda titulo, designacion, anio_cosecha (extraído del título), las claves foráneas a sus catálogos y una columna calculada, clave_natural, que se explica en la sección 3.4. La tabla resena guarda puntos, precio, descripcion y la fecha de carga.

## 3.3 Relaciones y cardinalidades

Todas las relaciones del modelo son de uno a muchos. No hizo falta ninguna tabla intermedia, porque en el dataset cada vino tiene a lo sumo una variedad y cada reseña un solo catador.

| Relación | Cardinalidad | Lectura |
| pais - provincia | 1 : 1..N | Un país tiene una o más provincias; cada provincia pertenece a un único país. |
| provincia - region | 1 : 0..N | Una provincia puede no tener regiones registradas; cada región pertenece a una sola provincia. |
| provincia - vino | 0..1 : 0..N | 59 reseñas no informan origen, por eso el vino puede no tener provincia. |
| region - vino | 0..1 : 0..N | La región es opcional (falta en el 16% de las filas). |
| zona - vino | 0..1 : 1..N | Solo los vinos de EE. UU. tienen zona. |
| bodega - vino | 1 : 1..N | Todo vino tiene bodega; toda bodega cargada tiene al menos un vino. |
| variedad - vino | 0..1 : 1..N | Una sola reseña no informa variedad. |
| vino - resena | 1 : 1..N | Cada reseña evalúa un vino; 694 vinos tienen más de una reseña. |
| catador - resena | 0..1 : 1..N | El 20,8% de las reseñas no tiene catador. |

::nota Tabla 3. Relaciones del modelo y su cardinalidad.

## 3.4 Decisiones de diseño

Las claves primarias son subrogadas (enteros AUTO_INCREMENT) en todas las tablas excepto resena. En resena se conserva el índice del CSV como clave para poder rastrear cualquier fila hasta el archivo original. Los nombres no sirven como clave primaria porque son largos, pueden corregirse y en algunos casos se repiten (hay dos regiones llamadas "Niagara Escarpment", una en Ontario y otra en Nueva York). Por eso el nombre de la región es único solo dentro de su provincia.

La tabla vino tiene, al mismo tiempo, una referencia a la provincia y otra a la región. Como la región ya determina la provincia, existía el riesgo de que un vino quedara asociado a una región de Mendoza y a una provincia de California. Para impedirlo, la clave foránea hacia region es compuesta: (id_region, id_provincia) referencia la clave alternativa del mismo nombre en region. Así el SGBD rechaza cualquier combinación incoherente, y una prueba de la sección 4.5 lo demuestra.

El vino necesitaba una clave natural única para no cargar dos veces la misma etiqueta, pero varias de sus columnas admiten NULL y MySQL permite NULL repetidos dentro de un índice UNIQUE. La solución fue una columna generada, clave_natural, que calcula un hash MD5 del título, la designación y las claves foráneas, reemplazando los NULL por un valor fijo. Sobre esa columna sí se puede definir una restricción UNIQUE confiable.

La columna usuario_twitter no se declaró UNIQUE porque dos catadores, Jeff Jenssen y Mike DeSimone, comparten la cuenta @worldwineguys. Con esa restricción, que a primera vista parecía lógica, la carga habría fallado.

Las claves foráneas no usan ON UPDATE CASCADE ni ON DELETE CASCADE. Las claves subrogadas no cambian nunca, y borrar en cascada un país arrastraría miles de reseñas por un error de operación. Se dejó el comportamiento por defecto (RESTRICT), que obliga a borrar primero los registros hijos.

La base usa utf8mb4 con la intercalación utf8mb4_0900_as_ci, que distingue acentos pero no mayúsculas. Con ella "Château" y "Chateau" son bodegas distintas, mientras que "Château La Barotte" y "Château la Barotte" se reconocen como la misma. En el CSV había 16.755 grafías de bodegas y la carga las redujo a 16.728.

## 3.5 Diagrama entidad-relación

La Figura 1 muestra el modelo en notación de pata de gallo, con las claves primarias subrayadas, las claves foráneas marcadas como FK y la cardinalidad escrita en cada extremo. El diagrama también se entrega por separado, en tamaño completo, en el archivo Diagrama_BD_Lucas_Llano.pdf.

::figura diagrama.png | Figura 1. Diagrama entidad-relación de la base vinos_tp3. | 16

# 4. Implementación en MySQL

## 4.1 Creación de tablas y restricciones

La sección 1 del script crea las nueve tablas con motor InnoDB, que es el que soporta claves foráneas y transacciones. Cada restricción tiene nombre propio (pk_, fk_, uq_, ck_), lo que hace legibles los mensajes de error. Como ejemplo se muestra la definición de resena, la tabla con más reglas.

```sql
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
```

El CHECK de puntos refleja una regla de negocio de la fuente: WineEnthusiast solo publica reseñas de 80 puntos o más. Los índices sobre puntos y precio se agregaron porque casi todas las consultas analíticas filtran o agrupan por esas columnas. Las claves foráneas ya tienen índice propio, porque InnoDB lo crea automáticamente.

## 4.2 Carga mediante una tabla de staging

La carga del CSV no se hace directamente sobre las tablas finales. Primero se lo vuelca en stg_resena, una tabla sin restricciones con las mismas columnas que el archivo, mediante LOAD DATA LOCAL INFILE. En la misma sentencia, NULLIF convierte los campos vacíos en NULL. Este paso intermedio separa dos problemas distintos: si algo falla en LOAD DATA, el error es de formato del archivo; si falla después, es de reglas del modelo.

```sql
LOAD DATA LOCAL INFILE 'datos/winemag_limpio.csv'
INTO TABLE stg_resena
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(id_original, @pais, @descripcion, @designacion, puntos, @precio, @provincia,
 @region_1, @region_2, @catador, @twitter, titulo, @variedad, bodega)
SET pais = NULLIF(@pais, ''), precio = NULLIF(@precio, ''), ...;
```

Declarar ESCAPED BY con una cadena vacía es necesario porque algunas descripciones contienen barras invertidas, que MySQL interpretaría como caracteres de escape. Las comillas dobles internas vienen duplicadas, como indica el estándar CSV, y MySQL las lee bien con OPTIONALLY ENCLOSED BY.

## 4.3 Transacción de carga y control de duplicados

La normalización completa (sección 3 del script) se ejecuta entre START TRANSACTION y COMMIT. Si algún INSERT viola una restricción, el cliente mysql detiene el script, la conexión se cierra sin COMMIT e InnoDB revierte todo, de modo que nunca quedan tablas cargadas a medias. Las sentencias DDL se ejecutan antes, fuera de la transacción, porque en MySQL cada CREATE TABLE produce un commit implícito.

Los duplicados se marcan con una función de ventana. Primero se calcula un hash MD5 de todos los campos de la fila. Luego ROW_NUMBER() numera las filas dentro de cada grupo de hash idéntico, y todas las que no son la primera quedan marcadas como duplicadas:

```sql
UPDATE stg_resena s
JOIN (
    SELECT id_original,
           ROW_NUMBER() OVER (PARTITION BY hash_fila ORDER BY id_original) AS nro
    FROM stg_resena
) d ON d.id_original = s.id_original
SET s.es_duplicado = (d.nro > 1);
```

Después se cargan las dimensiones de arriba hacia abajo (país, provincia, región) con INSERT ... SELECT DISTINCT, se resuelven las claves subrogadas en el staging con un UPDATE de siete LEFT JOIN y finalmente se insertan los vinos agrupados por su clave natural y las reseñas no duplicadas. El año de cosecha se obtiene del título con REGEXP_SUBSTR(titulo, '(19|20)[0-9]{2}'). Quedaron 3.613 vinos sin año, y en todos ellos el título dice "NV" (non vintage): son vinos sin cosecha declarada, algo habitual en espumantes y fortificados.

Al final de la carga, dos consultas de control verifican el resultado. La primera cuenta filas por tabla (los valores están en la Tabla 2). La segunda busca reseñas únicas del staging que no hayan llegado a la tabla final:

```ejecutar
SELECT (SELECT COUNT(*) FROM stg_resena) AS filas_csv,
       (SELECT SUM(es_duplicado) FROM stg_resena) AS duplicados,
       (SELECT COUNT(*) FROM resena) AS resenas_cargadas,
       (SELECT COUNT(*) FROM stg_resena s WHERE NOT s.es_duplicado
          AND NOT EXISTS (SELECT 1 FROM resena r WHERE r.id_resena = s.id_original)) AS resenas_perdidas
```

::nota Tabla 4. Control de la carga: 129.971 filas menos 9.983 duplicados dan exactamente las 119.988 reseñas cargadas.

## 4.4 Funciones, trigger, vista y procedimientos

La sección 4 del script agrega objetos que se reutilizan más adelante. Las funciones fn_rango_precio y fn_categoria_puntaje convierten el precio y los puntos en categorías discretas. La segunda sigue la escala oficial de WineEnthusiast: Aceptable (80-82), Bueno (83-86), Muy bueno (87-89), Excelente (90-93), Soberbio (94-97) y Clásico (98-100). Las dos se declaran DETERMINISTIC y NO SQL, como exige MySQL cuando el registro binario está activo.

El trigger tg_resena_validar se ejecuta antes de cada INSERT en resena. Recorta los espacios de la descripción y, si quedan menos de diez caracteres, cancela la operación con SIGNAL SQLSTATE '45000' y un mensaje propio. Es una regla que un CHECK no puede expresar con comodidad, porque necesita primero transformar el dato.

La vista v_hechos_resena une la tabla de hechos con todas sus dimensiones y agrega las dos categorías calculadas. No duplica datos, pero simplifica mucho las consultas analíticas, que pasan de ocho JOIN a una sola tabla en el FROM. Queda el procedimiento sp_variedades_region, que recibe el nombre de una región y una cantidad, y devuelve las variedades más reseñadas de esa región (se usa en la consulta C03).

## 4.5 Pruebas de integridad

Para verificar que las restricciones se cumplen, el script intenta violarlas a propósito. El procedimiento sp_probar recibe una sentencia SQL, la ejecuta con PREPARE/EXECUTE y atrapa el error con un CONTINUE HANDLER. De esa forma el script sigue corriendo y deja registrado el mensaje del servidor. Cada caso de la tabla siguiente es un INSERT o DELETE diseñado para fallar.

| Prueba | Respuesta del servidor |
| Puntaje fuera de escala (120) | Check constraint 'ck_resena_puntos' is violated. |
| Precio negativo | Check constraint 'ck_resena_precio' is violated. |
| FK a un vino inexistente | Cannot add or update a child row: a foreign key constraint fails (fk_resena_vino) |
| Clave primaria repetida | Duplicate entry '0' for key 'resena.PRIMARY' |
| País duplicado (UNIQUE) | Duplicate entry 'Argentina' for key 'pais.uq_pais_nombre' |
| Borrar un país con vinos (RESTRICT) | Cannot delete or update a parent row: a foreign key constraint fails (fk_provincia_pais) |
| Descripción vacía (trigger) | La descripción de la reseña es demasiado corta (mínimo 10 caracteres). |
| Región de otra provincia (FK compuesta) | Cannot add or update a child row: a foreign key constraint fails (fk_vino_region) |

::nota Tabla 5. Resultado de las pruebas de integridad. Los mensajes de clave foránea se abreviaron al nombre de la restricción.

Las ocho operaciones fueron rechazadas. La última prueba intenta crear un vino con provincia Mendoza y región Napa Valley. Las dos claves existen por separado, de modo que dos claves foráneas simples la habrían aceptado. La clave compuesta es la que detecta que esa región no pertenece a esa provincia.

## 4.6 Transacciones con SAVEPOINT

El último bloque de la sección 5 del script simula una operación de mantenimiento. Dentro de una transacción aumenta un 10% el precio de los vinos argentinos, crea un SAVEPOINT, borra las reseñas de menos de 82 puntos de un catador y después deshace los cambios en dos pasos.

```sql
START TRANSACTION;
UPDATE resena r JOIN vino v ... SET r.precio = r.precio * 1.10 WHERE pa.nombre = 'Argentina' ...;
SAVEPOINT antes_de_borrar;
DELETE r FROM resena r JOIN catador c ... WHERE c.nombre = 'Michael Schachner' AND r.puntos < 82;
ROLLBACK TO SAVEPOINT antes_de_borrar; -- vuelve el borrado
ROLLBACK; -- descarta también el aumento
```

El precio medio de Argentina era 24,58 dólares antes de empezar, pasó a 27,03 dentro de la transacción y volvió a 24,58 después del ROLLBACK. El DELETE había afectado 483 filas, que se recuperaron al volver al savepoint. Así se comprueba la atomicidad: ninguna de las dos modificaciones quedó persistida.

# 5. Consultas SQL

Esta sección presenta las consultas de la sección 6 del script, numeradas de C01 a C14. Cada una incluye el código, el resultado (a veces recortado a las primeras filas) y una interpretación. Salvo aclaración, todas trabajan sobre las 119.988 reseñas sin duplicados, cuyo puntaje promedio general es 88,44 y cuyo precio promedio es 35,62 dólares.

## 5.1 Vinos y reseñas por país (C01)

Responde la primera pregunta de la consigna, la cantidad de vinos por país. Además de COUNT(DISTINCT), la consulta usa SUM(COUNT(*)) OVER () para calcular el porcentaje sobre el total sin una subconsulta aparte, ya que la función de ventana se evalúa después del GROUP BY.

::consulta C01 15

::figura fig_paises.png | Figura 2. Reseñas por país (los 15 con más reseñas). | 14

El dataset está muy concentrado: Estados Unidos aporta el 42,07% de las reseñas y, junto con Francia e Italia, llega casi al 74%. Esto es un sesgo de la fuente, que es una revista estadounidense, y conviene tenerlo presente en todo el análisis. Un promedio "global" es en buena medida un promedio de vinos de esos tres países.

La cantidad de vinos y de reseñas es casi igual en todos los países. La mayoría de las etiquetas se reseñó una sola vez, y solo 694 vinos tienen más de una reseña. En cuanto a puntajes, Austria (90,13) y Alemania (89,90) encabezan la lista, mientras que Chile (86,46) y Argentina (86,65) quedan últimos entre los quince países con más reseñas.

## 5.2 Variedades más comunes en una región (C02 y C03)

La consigna pide las variedades más comunes en una región específica. Se resolvió de dos formas: con una consulta directa sobre la provincia de Mendoza y con el procedimiento almacenado sp_variedades_region para la región de Napa Valley.

::consulta C02 10

El Malbec reúne 1.265 de las 3.038 reseñas de Mendoza, un 41,6%. Su puntaje promedio (87,55) supera al del Cabernet Sauvignon y al del Chardonnay de la misma provincia, aunque los mejor puntuados son los cortes bordeleses (89,97), que también son los más caros. El Torrontés, la blanca emblemática del país, tiene el precio promedio más bajo (12,35) y uno de los puntajes más bajos.

::consulta C03 8

En Napa Valley el Cabernet Sauvignon es todavía más dominante: tiene más reseñas que las cuatro variedades siguientes juntas, con un precio promedio de 71,27 dólares, dos veces y media el del Malbec mendocino. Al estar en un procedimiento, la misma consulta sirve para cualquier otra región con solo cambiar el parámetro.

## 5.3 Precio promedio por puntuación (C04)

::consulta C04 21

::figura fig_precio_puntos.png | Figura 3. Precio promedio por puntuación (eje vertical en escala logarítmica). | 14

El precio promedio crece con cada punto, pero no de forma lineal. Entre 80 y 90 puntos pasa de 16,37 a 36,99 dólares, algo más del doble. Entre 90 y 100 puntos se multiplica por trece y llega a 485,95. Por eso la Figura 3 usa una escala logarítmica, en la que la curva se vuelve casi una recta: cada punto adicional encarece el vino en un porcentaje parecido.

Los mínimos y máximos muestran mucha dispersión. Con 88 puntos está el vino más caro de todo el dataset, un Château les Ormes Sorbet de 3.300 dólares, y ya con 87 puntos hay vinos de 5 dólares. El precio predice el puntaje en promedio, pero no garantiza nada en el caso individual.

## 5.4 Bodegas mejor puntuadas (C05)

::consulta C05 10

El filtro HAVING COUNT(*) >= 30 evita que el ranking lo encabecen bodegas con dos o tres vinos excepcionales. Cayuse, del valle de Walla Walla (EE. UU.), lidera con 94,07 de promedio en 75 reseñas. Austria aparece tres veces en el top 10, lo que coincide con su promedio nacional alto en C01. Llama la atención la diferencia de precios entre bodegas de puntaje similar: Eichinger promedia 92,81 puntos con vinos de 28 dólares, mientras que Louis Roederer necesita 129 dólares para llegar a 93,25.

## 5.5 Subconsulta correlacionada: vinos caros para su provincia (C06)

Esta consulta busca vinos argentinos que cuestan más del triple del promedio de su propia provincia. La subconsulta se reevalúa para cada fila de la consulta exterior, porque depende de v.id_provincia, y ese es el rasgo que la hace correlacionada.

::consulta C06 10

Ocho de los diez vinos son de Viña Cobos y todos cuestan 175 dólares o más, contra un promedio provincial de 25,10. Son vinos de alta gama, de viñedos únicos como Marchiori, que el mercado internacional paga entre siete y nueve veces más que el Malbec mendocino típico. Sus puntajes (de 87 a 95) son buenos, pero no tan superiores como el precio haría suponer.

## 5.6 Relación calidad-precio (C07)

::consulta C07 10

Con al menos 93 puntos y un precio de hasta 20 dólares, el primer lugar es para un Madiran francés de 12 dólares, con 7,75 puntos por dólar. En el top 10 hay tres vinos franceses (dos de Madiran), dos portugueses y dos austríacos, y casi todos son de variedades o regiones menos conocidas para el consumidor general (Tannat, Touriga Nacional, Furmint, Grüner Veltliner). Una explicación posible es que la demanda internacional por estas variedades todavía no subió sus precios.

## 5.7 Perfil de los catadores (C08)

Esta consulta combina varias agregaciones: promedio, desvío estándar muestral (STDDEV_SAMP) y una agregación condicional que calcula el porcentaje de reseñas de 90 puntos o más con AVG(CASE ...).

::consulta C08 19

Roger Voss escribió 23.560 reseñas, casi una de cada cinco del dataset. Los catadores no puntúan igual: Anne Krebiehl promedia 90,63 y da 90 o más en dos de cada tres reseñas, mientras que Alexander Peartree promedia 85,78 y apenas llega a 90 en el 3,1% de los casos. Sería apresurado concluir que uno es más exigente que el otro, porque cada catador cubre países distintos (Krebiehl reseña sobre todo Austria y Francia; Peartree, vinos de Virginia, Michigan y Texas). Las dos variables están confundidas, y separarlas requeriría comparar catadores dentro de un mismo país y variedad.

## 5.8 Las tres variedades principales de cada país (C09)

La consulta encadena dos CTE. La primera elige los seis países con más reseñas y la segunda numera las variedades dentro de cada país con ROW_NUMBER() OVER (PARTITION BY pais ...). La consulta final filtra los tres primeros puestos.

::consulta C09 18

Cada país tiene una identidad bastante clara. Estados Unidos es sobre todo Pinot Noir, Francia es cortes bordeleses, España es Tempranillo y Chile combina Cabernet Sauvignon, Sauvignon Blanc y Carmenère. Italia y Portugal muestran un límite del dataset: sus variedades principales son "Red Blend" y "Portuguese Red", categorías genéricas que agrupan cortes locales muy diferentes entre sí.

## 5.9 Cuartiles de precio (C10)

NTILE(4) divide las reseñas con precio en cuatro grupos de igual tamaño ordenados por precio. Así se puede responder sin elegir cortes arbitrarios si los vinos más caros reciben mejores puntajes.

::consulta C10 4

El puntaje sube en cada cuartil. El más barato (hasta 17 dólares) promedia 86,03 puntos y solo el 6,6% de sus vinos llega a 90. El más caro (desde 42 dólares) promedia 90,99 y el 73,6% supera esa marca. Entre los extremos hay casi cinco puntos de diferencia, que es mucho para una escala que en la práctica va de 80 a 100.

## 5.10 Países sin vinos sobresalientes (C11)

::consulta C11 15

NOT EXISTS devuelve los países que no tienen ninguna reseña de 95 puntos o más. La primera versión de la consulta pedía al menos 500 reseñas y no devolvió filas: todos los productores grandes tienen algún vino excepcional. Con un umbral de 50 aparecen doce países, encabezados por Israel (466 reseñas, máximo 94), Grecia y Canadá. Más que una cuestión de calidad, parece un tema de volumen: con pocas reseñas es menos probable que aparezca un vino de 95 o más.

## 5.11 Evolución por año de cosecha (C12)

La función LAG() trae el promedio del año anterior a la fila actual, lo que permite calcular la variación interanual sin unir la tabla consigo misma.

::consulta C12 16

Entre 2000 y 2015 el puntaje promedio se mueve en un rango angosto, de 87,39 a 88,95, y ninguna variación interanual supera 0,63 puntos. Las diferencias de cosecha que tanto importan en una región concreta se diluyen cuando se promedian todos los países. La cantidad de reseñas, en cambio, crece hasta 2012-2013 y cae después. La caída del precio en 2015 (25,57 frente a 34,08 en 2014) tiene una explicación probable: de las cosechas más recientes se reseñan primero los vinos jóvenes y baratos, mientras que los de guarda salen al mercado años después.

## 5.12 Variedades por encima del promedio (C13)

::consulta C13 12

La subconsulta escalar del HAVING calcula el promedio general (88,44) una sola vez. De las variedades con más de mil reseñas, doce lo superan. Nebbiolo es la mejor puntuada (90,32), aunque es de las más caras. Desde el punto de vista del comprador resultan más llamativas Grüner Veltliner (89,99 a 28 dólares) y Riesling (89,48 a 33 dólares), que logran puntajes de primer nivel con precios cercanos al promedio.

## 5.13 La mejor bodega de cada país (C14)

::consulta C14 12

RANK() se calcula sobre una tabla derivada que ya tiene el promedio por bodega. Se usó RANK en lugar de ROW_NUMBER para que, si dos bodegas empataran en el primer puesto, aparecieran ambas. En Argentina el primer lugar es para Riglos, con 91 puntos de promedio en 13 reseñas.

# 6. Análisis multidimensional

## 6.1 Hechos y dimensiones

El análisis multidimensional mira los datos como un cubo. Las celdas son los hechos (cada reseña, con sus medidas: cantidad, puntos y precio) y los ejes son las dimensiones (país, provincia, región, variedad, rango de precio y categoría de puntaje). El modelo relacional del capítulo 3 ya tiene esa forma: resena es la tabla de hechos y el resto son dimensiones, en un esquema estrella con la jerarquía geográfica normalizada (esquema copo de nieve). La vista v_hechos_resena lo presenta desnormalizado para que las consultas OLAP sean más simples.

MySQL no tiene un motor OLAP, pero las operaciones clásicas se pueden expresar en SQL. La sección 7 del script incluye una consulta para cada una: roll-up, drill-down, pivot, slice, dice y cubo.

## 6.2 Roll-up: país y rango de precio (M01)

GROUP BY ... WITH ROLLUP agrega filas de subtotal por cada nivel de la jerarquía y un total general. En esas filas la columna agregada aparece como NULL, y la función GROUPING() permite distinguir ese NULL de uno real y reemplazarlo por un rótulo.

::consulta M01 22

En los tres países el puntaje sube con cada rango de precio y la pendiente es parecida: de unos 85 puntos por debajo de 15 dólares a unos 92 por encima de 100. Las diferencias entre países aparecen sobre todo en la distribución. España tiene proporcionalmente más vinos caros que Chile, y eso explica buena parte de su promedio más alto (87,24 contra 86,46). Dentro de cada franja de precio, los tres países están a menos de un punto.

## 6.3 Drill-down: Argentina por provincia y región (M02)

::consulta M02 25

Al bajar un nivel en la jerarquía geográfica se ve que el 85,7% de las reseñas argentinas corresponde a Mendoza. WineEnthusiast agrupa el resto del país en una provincia llamada "Other", donde están Salta, Patagonia y San Juan. Dentro de Mendoza las diferencias son grandes: Perdriel promedia 90,28 puntos con un precio medio de 82,88 dólares, mientras que Maipú queda en 84,96.

El drill-down también deja ver un problema de calidad de datos que el perfil inicial no había mostrado: "Uco Valley" y "Valle de Uco" son la misma región escrita en dos idiomas y figuran como regiones distintas. Para unificarlas haría falta una tabla de equivalencias cargada a mano, porque no hay una regla automática que detecte ese tipo de sinónimos.

## 6.4 Pivot: país y categoría de puntaje (M03)

El pivot convierte los valores de una dimensión en columnas. MySQL no tiene el operador PIVOT, así que cada columna se arma con una expresión condicional. AVG(categoria = 'Excelente') devuelve directamente la proporción, porque la comparación vale 1 o 0.

::consulta M03 12

::figura fig_categorias.png | Figura 4. Distribución de categorías de puntaje por país (países con al menos 1.000 reseñas). | 15

El orden de la tabla coincide con el de C01, pero acá se ve de dónde sale la diferencia. Austria y Alemania tienen más de la mitad de sus vinos en Excelente o mejor. En Chile y Argentina, la categoría más frecuente es Bueno (83-86 puntos). Todos los países tienen algún vino soberbio; lo que cambia es dónde se concentra la mayoría de sus reseñas.

## 6.5 Slice: el Malbec (M04)

Hacer un slice es fijar una dimensión en un valor y analizar las demás. Acá se fija variedad = 'Malbec'.

::consulta M04 10

Argentina concentra el 57% de las reseñas de Malbec del dataset (1.402 de 2.446), pero su puntaje promedio (87,46) queda por debajo del francés (89,65). El Malbec francés reseñado proviene casi todo de Cahors (361 de 413 reseñas), así que la comparación es entre un país entero y una sola denominación tradicional. Chile ofrece la mejor relación de puntos por dólar (4,51) porque su Malbec es el más barato.

## 6.6 Dice: subcubo de tres dimensiones (M05)

El dice restringe varias dimensiones a la vez y obtiene un subcubo. Se compararon tres países, dos variedades y dos rangos de precio.

::consulta M05 12

Al controlar el precio cambian algunas conclusiones. En C01 Chile y Argentina estaban por debajo del promedio, pero un Cabernet Sauvignon chileno de 15 a 29 dólares (87,48) puntúa mejor que uno estadounidense del mismo rango (86,88). En el rango de 30 a 59 dólares, el Malbec argentino (89,94) supera al de Estados Unidos (88,90) por un punto. Los promedios nacionales de C01 mezclaban calidad con composición de precios, y el dice los separa.

## 6.7 Cubo: país y variedad (M06)

Un cubo calcula todas las combinaciones de agregación posibles. MySQL no implementa GROUP BY CUBE, así que se lo construye con UNION ALL de los cuatro agrupamientos: (país, variedad), (país), (variedad) y el total.

::consulta M06 16

En el cubo se puede leer el mismo dato en distintos niveles. El Pinot Noir es la mejor de las tres variedades en el total (89,65) y en Francia (89,80) y Estados Unidos (89,62), con una diferencia mínima entre ambos países. En Italia hay que mirar la cantidad antes que el promedio: su Pinot Noir tiene solo seis reseñas, muy pocas para sacar conclusiones.

## 6.8 Matriz país y rango de precio (M07)

::consulta M07 10

::figura fig_calor.png | Figura 5. Puntaje promedio por país y rango de precio. | 15

En los diez países el puntaje sube con cada rango de precio, así que todas las filas crecen de izquierda a derecha. Lo que cambia es el punto de partida de cada fila. Austria y Alemania tienen los valores más altos en casi todas las columnas. Un vino austríaco de menos de 15 dólares (87,90 puntos) supera en promedio a los vinos argentinos, chilenos, españoles, estadounidenses, italianos y franceses de 15 a 29 dólares. En el extremo superior, Portugal (94,08) y Austria (94,04) son los únicos que superan los 94 puntos.

# 7. Desafíos y soluciones

El primer desafío apareció antes de escribir SQL: el archivo entregado no era el CSV original sino una versión dañada por Excel, con filas partidas y codificación incorrecta. Importarlo directamente habría cargado textos ilegibles y unas 430 reseñas con columnas corridas. La solución fue reconstruir cada línea desde el XML del libro y corregir la codificación con un script que además verifica que se obtengan las 129.971 filas esperadas.

Después hubo que definir la granularidad de la tabla vino. La intuición inicial (un vino por título, con su precio) chocaba con los datos, que mostraban el mismo título con precios distintos. Mover el precio a resena y construir una clave natural con columna generada resolvió el problema sin perder información.

Algo parecido pasó con la integridad entre provincia y región dentro de vino. Una clave foránea simple a cada tabla dejaba pasar combinaciones imposibles. La clave foránea compuesta contra una clave alternativa de region lo impide, como muestra la prueba de la sección 4.5.

También hubo que ajustar la configuración de MySQL. LOAD DATA LOCAL INFILE está deshabilitado por defecto desde la versión 8, y hubo que activar local_infile tanto en el servidor como en el cliente. Además, la intercalación por defecto de MySQL 8 (utf8mb4_0900_ai_ci) ignora acentos, lo que habría fusionado bodegas distintas como "Château" y "Chateau". Se eligió utf8mb4_0900_as_ci para distinguir acentos pero no mayúsculas.

A eso se sumó que MySQL no tiene algunas operaciones: no hay GROUP BY CUBE ni operador PIVOT, y una consulta de prueba no puede fallar sin detener el script. Se usaron alternativas estándar: UNION ALL de agrupamientos para el cubo, agregación condicional para el pivot y un procedimiento con CONTINUE HANDLER para las pruebas de integridad.

El rendimiento trajo un problema que tardó en aparecer. En algunas ejecuciones completas del script la consulta C06 tardaba casi tres minutos, mientras que corrida sola, con la base ya cargada, tardaba unos 20 segundos. La causa eran las estadísticas: justo después de una carga masiva MySQL no las tiene actualizadas y elige un mal plan para la subconsulta correlacionada. Con un ANALYZE TABLE al final de la carga el problema desapareció, y el script completo (carga de casi 130.000 filas, trigger en cada INSERT y todas las consultas) quedó en un minuto y medio aproximadamente. C06 sigue siendo la consulta más costosa, y por eso se la limitó a un país: su costo crece con el cuadrado de las filas que evalúa.

# 8. Conclusiones y líneas futuras

## 8.1 Conclusiones

Al pasar del archivo plano a nueve tablas normalizadas desapareció la repetición del CSV, y el SGBD pasó a controlar reglas que antes no verificaba nadie: puntajes en escala, precios positivos, regiones coherentes con su provincia y reseñas siempre asociadas a un vino existente. Las ocho pruebas de integridad y la transacción revertida muestran que esas reglas funcionan.

Sobre los datos en sí, el análisis muestra que el precio y el puntaje están asociados de forma consistente. El cuartil más caro supera al más barato por casi cinco puntos, y la relación se mantiene en todos los países y rangos analizados. También muestra que los promedios nacionales engañan si no se controla el precio. Chile y Argentina parecen rezagados en C01, pero dentro de una misma franja de precio compiten de igual a igual con Estados Unidos. Austria, Alemania y Portugal destacan por la calidad de sus vinos baratos, y la mejor relación calidad-precio aparece en variedades y denominaciones poco conocidas.

Hay que tener en cuenta algunos límites: el dataset sobrerrepresenta a Estados Unidos, el puntaje depende en parte del catador asignado (y cada catador cubre regiones distintas) y las categorías como "Red Blend" agrupan vinos que no tienen nada en común.

## 8.2 Líneas futuras

La columna description, con casi 120.000 notas de cata, prácticamente no se usó en este trabajo, y es la que más potencial tiene. Con técnicas de procesamiento de lenguaje natural se podrían identificar los descriptores típicos de cada variedad o predecir la variedad a partir del texto, que es el desafío que plantea el enunciado al hablar de los sommeliers. MySQL ofrece índices FULLTEXT que permitirían una primera exploración sin salir del SGBD.

Otras extensiones posibles: un modelo de regresión que estime el puntaje a partir del precio, el país y la variedad, separando el efecto del catador; una tabla de sinónimos de regiones y variedades para unificar casos como "Uco Valley" y "Valle de Uco"; y la carga del modelo en una herramienta OLAP o de visualización interactiva que permita navegar el cubo sin escribir SQL.
