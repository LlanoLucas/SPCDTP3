# Diagrama entidad-relación (pata de gallo), A4 apaisado.
from pathlib import Path

import pymupdf  # para pasar el PDF a PNG
from reportlab.lib.pagesizes import A4, landscape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

RAIZ = Path(__file__).resolve().parent.parent
PDF = RAIZ / "Diagrama_BD_Lucas_Llano.pdf"
PNG = RAIZ / "herramientas" / "salida" / "diagrama.png"

FUENTES = Path("C:/Windows/Fonts")
pdfmetrics.registerFont(TTFont("Arial", str(FUENTES / "arial.ttf")))
pdfmetrics.registerFont(TTFont("Arial-Bold", str(FUENTES / "arialbd.ttf")))
pdfmetrics.registerFont(TTFont("Arial-Italic", str(FUENTES / "ariali.ttf")))

ANCHO, ALTO = landscape(A4)
FILA, CABECERA = 13, 18
TINTA, GRIS, AZUL, CELESTE = "#1d1d1b", "#6b6a66", "#1c5cab", "#e6eefa"

# tabla: (x, y medido desde arriba, ancho, columnas)
ENTIDADES = {
    "pais": (30, 60, 175, [
        ("PK", "id_pais", "SMALLINT"),
        ("UQ", "nombre", "VARCHAR(40)")]),
    "provincia": (280, 60, 210, [
        ("PK", "id_provincia", "SMALLINT"),
        ("", "nombre", "VARCHAR(50)"),
        ("FK", "id_pais", "SMALLINT")]),
    "region": (565, 60, 200, [
        ("PK", "id_region", "SMALLINT"),
        ("", "nombre", "VARCHAR(60)"),
        ("FK", "id_provincia", "SMALLINT")]),
    "bodega": (30, 222, 175, [
        ("PK", "id_bodega", "INT"),
        ("UQ", "nombre", "VARCHAR(80)")]),
    "variedad": (30, 284, 175, [
        ("PK", "id_variedad", "SMALLINT"),
        ("UQ", "nombre", "VARCHAR(50)")]),
    "zona": (30, 346, 175, [
        ("PK", "id_zona", "TINYINT"),
        ("UQ", "nombre", "VARCHAR(30)")]),
    "vino": (280, 220, 210, [
        ("PK", "id_vino", "INT"),
        ("", "titulo", "VARCHAR(150)"),
        ("", "designacion", "VARCHAR(100) NULL"),
        ("", "anio_cosecha", "SMALLINT NULL"),
        ("FK", "id_bodega", "INT"),
        ("FK", "id_variedad", "SMALLINT NULL"),
        ("FK", "id_provincia", "SMALLINT NULL"),
        ("FK", "id_region", "SMALLINT NULL"),
        ("FK", "id_zona", "TINYINT NULL"),
        ("UQ", "clave_natural", "CHAR(32)")]),
    "resena": (565, 220, 200, [
        ("PK", "id_resena", "INT"),
        ("FK", "id_vino", "INT"),
        ("FK", "id_catador", "TINYINT NULL"),
        ("", "puntos", "TINYINT (80-100)"),
        ("", "precio", "DECIMAL(7,2) NULL"),
        ("", "descripcion", "TEXT"),
        ("", "fecha_carga", "TIMESTAMP")]),
    "catador": (565, 400, 200, [
        ("PK", "id_catador", "TINYINT"),
        ("UQ", "nombre", "VARCHAR(40)"),
        ("", "usuario_twitter", "VARCHAR(30) NULL")]),
}

# (puntos de la línea, extremo de un lado, extremo del otro, texto)
# extremos: '1' = uno y solo uno, '01' = cero o uno, '1N' = uno o muchos, '0N' = cero o muchos
RELACIONES = [
    ([(205, 85), (280, 85)], "1", "1N", "tiene"),
    ([(490, 92), (565, 92)], "1", "0N", "contiene"),
    ([(330, 121), (330, 220)], "01", "0N", "origen"),
    ([(695, 121), (695, 175), (450, 175), (450, 220)], "01", "0N", "denominación"),
    ([(205, 247), (280, 247)], "1", "1N", "elabora"),
    ([(205, 309), (280, 309)], "01", "1N", "uva"),
    ([(205, 371), (280, 371)], "01", "1N", "área"),
    ([(490, 280), (565, 280)], "1", "1N", "recibe"),
    ([(665, 400), (665, 333)], "01", "1N", "escribe"),
]
TEXTO_CARD = {"1": "1", "01": "0..1", "1N": "1..N", "0N": "0..N"}


def y(v):
    """Convierte una coordenada medida desde arriba al sistema de reportlab."""
    return ALTO - v


def alto(atributos):
    return CABECERA + FILA * len(atributos) + 4


def dibujar_entidad(c, nombre, x, top, ancho, atributos):
    h = alto(atributos)
    c.setStrokeColor(TINTA)
    c.setLineWidth(1)
    c.setFillColor("white")
    c.rect(x, y(top + h), ancho, h, fill=1)
    c.setFillColor(CELESTE)
    c.rect(x, y(top + CABECERA), ancho, CABECERA, fill=1)
    c.setFillColor(TINTA)
    c.setFont("Arial-Bold", 9.5)
    c.drawCentredString(x + ancho / 2, y(top + 12.5), nombre.upper())
    for i, (marca, col, tipo) in enumerate(atributos):
        base = y(top + CABECERA + FILA * (i + 1) - 3)
        if marca:
            c.setFillColor(AZUL if marca == "PK" else GRIS)
            c.setFont("Arial-Bold", 7)
            c.drawString(x + 5, base, marca)
        c.setFillColor(TINTA)
        fuente = "Arial-Bold" if marca == "PK" else "Arial"
        c.setFont(fuente, 8)
        c.drawString(x + 24, base, col)
        if marca == "PK":
            c.line(x + 24, base - 1.5, x + 24 + pdfmetrics.stringWidth(col, fuente, 8), base - 1.5)
        c.setFillColor(GRIS)
        c.setFont("Arial", 7)
        c.drawRightString(x + ancho - 5, base, tipo)
    c.setFillColor(TINTA)


def marca_extremo(c, punta, previo, tipo):
    """Dibuja la terminación pata de gallo en 'punta', con la línea viniendo de 'previo'."""
    (x1, y1), (x0, y0) = punta, previo
    dx, dy = x0 - x1, y0 - y1
    largo = (dx * dx + dy * dy) ** 0.5
    ux, uy = dx / largo, dy / largo          # hacia adentro de la línea
    px, py = -uy, ux                          # perpendicular

    def punto(d, lateral=0):
        return x1 + ux * d + px * lateral, y1 + uy * d + py * lateral

    def barra(d):
        a, b = punto(d, 5), punto(d, -5)
        c.line(*a, *b)

    def circulo(d):
        cx, cy = punto(d)
        c.setFillColor("white")
        c.circle(cx, cy, 3.2, fill=1)
        c.setFillColor(TINTA)

    def pata():
        v = punto(9)
        for lat in (-6, 0, 6):
            c.line(*v, *punto(0, lat))

    if tipo == "1":
        barra(5); barra(9)
    elif tipo == "01":
        barra(5); circulo(12)
    elif tipo == "1N":
        pata(); barra(12)
    elif tipo == "0N":
        pata(); circulo(14)


def dibujar_relacion(c, ruta, ext_origen, ext_destino, etiqueta):
    pts = [(px, y(py)) for px, py in ruta]
    c.setStrokeColor(TINTA)
    c.setLineWidth(0.9)
    for a, b in zip(pts, pts[1:]):
        c.line(*a, *b)
    marca_extremo(c, pts[0], pts[1], ext_origen)
    marca_extremo(c, pts[-1], pts[-2], ext_destino)

    # cardinalidad escrita junto a cada extremo
    c.setFont("Arial", 6.5)
    c.setFillColor(AZUL)
    for punta, previo, tipo in ((pts[0], pts[1], ext_origen), (pts[-1], pts[-2], ext_destino)):
        (x1, y1), (x0, y0) = punta, previo
        if x1 == x0:   # tramo vertical
            sentido = 1 if y0 > y1 else -1
            c.drawString(x1 + 8, y1 + sentido * 18 - 2, TEXTO_CARD[tipo])
        else:          # tramo horizontal
            sentido = 1 if x0 > x1 else -1
            c.drawCentredString(x1 + sentido * 20, y1 + 6, TEXTO_CARD[tipo])

    # verbo de la relación en el tramo más largo
    a, b = max(zip(pts, pts[1:]), key=lambda s: abs(s[0][0] - s[1][0]) + abs(s[0][1] - s[1][1]))
    mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    c.setFont("Arial-Italic", 7)
    c.setFillColor(GRIS)
    if a[0] == b[0]:
        c.drawRightString(mx - 6, my - 2, etiqueta)
    else:
        c.drawCentredString(mx, my - 9, etiqueta)
    c.setFillColor(TINTA)


def dibujar_leyenda(c, x, top):
    c.setFont("Arial-Bold", 8.5)
    c.drawString(x, y(top), "Referencias")
    c.setFont("Arial", 7.5)
    c.setStrokeColor(TINTA)
    filas = [("1", "uno y solo uno (1)"), ("01", "cero o uno (0..1)"),
             ("1N", "uno o muchos (1..N)"), ("0N", "cero o muchos (0..N)")]
    for i, (tipo, texto) in enumerate(filas):
        yy = y(top + 16 + i * 15)
        c.line(x, yy, x + 40, yy)
        marca_extremo(c, (x + 40, yy), (x, yy), tipo)
        c.drawString(x + 50, yy - 2.5, texto)
    x2 = x + 175
    claves = [("PK", AZUL, "clave primaria (subrayada)"), ("FK", GRIS, "clave foránea"),
              ("UQ", GRIS, "restricción UNIQUE")]
    for i, (marca, color, texto) in enumerate(claves):
        yy = y(top + 16 + i * 15)
        c.setFillColor(color)
        c.setFont("Arial-Bold", 7)
        c.drawString(x2, yy - 2.5, marca)
        c.setFillColor(TINTA)
        c.setFont("Arial", 7.5)
        c.drawString(x2 + 20, yy - 2.5, texto)
    c.setFont("Arial-Italic", 7)
    c.setFillColor(GRIS)
    c.drawString(x2, y(top + 16 + 3 * 15) - 2.5,
                 "vino(id_region, id_provincia) referencia region(id_region, id_provincia)")
    c.setFillColor(TINTA)


def generar():
    PNG.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(PDF), pagesize=(ANCHO, ALTO))
    c.setTitle("Diagrama entidad-relación vinos_tp3")
    c.setAuthor("Lucas Llano")
    c.setFont("Arial-Bold", 13)
    c.drawString(30, y(32), "Diagrama entidad-relación de la base vinos_tp3")
    c.setFont("Arial", 8.5)
    c.setFillColor(GRIS)
    c.drawString(30, y(45), "TP3 · Reseñas de vinos WineEnthusiast · MySQL 8.4 · Lucas Llano · 14/10/2026")
    c.setFillColor(TINTA)

    for ruta, o, d, etiqueta in RELACIONES:
        dibujar_relacion(c, ruta, o, d, etiqueta)
    for nombre, (x, top, ancho, atributos) in ENTIDADES.items():
        dibujar_entidad(c, nombre, x, top, ancho, atributos)
    dibujar_leyenda(c, 30, 440)

    c.setFont("Arial", 7)
    c.setFillColor(GRIS)
    c.drawString(30, y(ALTO - 20),
                 "Notación de pata de gallo (crow's foot). Cada relación se lee desde la "
                 "entidad padre: por ejemplo, un país tiene una o muchas provincias y cada "
                 "provincia pertenece a un único país.")
    c.showPage()
    c.save()

    doc = pymupdf.open(PDF)
    doc[0].get_pixmap(dpi=220).save(PNG)
    print("listo:", PDF.name)


if __name__ == "__main__":
    generar()
