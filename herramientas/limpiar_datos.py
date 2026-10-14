# En el Excel cada fila tiene una línea entera del CSV original en la columna A.
# Como se abrió con ';' de separador, las descripciones que tenían punto y coma
# quedaron cortadas en varias celdas. Además el texto tiene mal la codificación
# (UTF-8 leído como Windows-1252), por eso aparece "VulkÃ " en vez de "Vulkà".
import csv
import io
import re
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
ORIGEN = RAIZ / "Entregable 3 - Documentación extra .xlsm"
DESTINO = RAIZ / "datos" / "winemag_limpio.csv"
NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
COLUMNAS = ["id", "country", "description", "designation", "points", "price",
            "province", "region_1", "region_2", "taster_name",
            "taster_twitter_handle", "title", "variety", "winery"]


# 'C12' -> 2 (columna C, empezando de 0)
def indice_columna(ref):
    letras = re.match(r"[A-Z]+", ref).group()
    n = 0
    for ch in letras:
        n = n * 26 + ord(ch) - 64
    return n - 1


# 'Ã©' -> 'é': se vuelve a pasar el texto a bytes cp1252 y se lee como utf-8
def corregir_codificacion(texto):
    # ojo: cp1252 no tiene 0x81, 0x8D, 0x8F, 0x90 ni 0x9D y Excel los dejó como
    # caracteres de control, esos se agregan como bytes a mano
    crudo = bytearray()
    for ch in texto:
        try:
            crudo += ch.encode("cp1252")
        except UnicodeEncodeError:
            if ord(ch) > 255:
                return texto
            crudo.append(ord(ch))
    try:
        return crudo.decode("utf-8")
    except UnicodeDecodeError:
        return texto


# el xlsm es un zip con xml adentro. Los textos están en sharedStrings y la
# hoja solo tiene el número de cada texto
def leer_lineas(libro):
    textos = []
    for _, el in ET.iterparse(libro.open("xl/sharedStrings.xml")):
        if el.tag == NS + "si":
            textos.append("".join(t.text or "" for t in el.iter(NS + "t")))
            el.clear()
    for _, el in ET.iterparse(libro.open("xl/worksheets/sheet1.xml")):
        if el.tag != NS + "row":
            continue
        celdas = {}
        for c in el.findall(NS + "c"):
            v = c.find(NS + "v")
            if v is not None:
                celdas[indice_columna(c.get("r"))] = (
                    textos[int(v.text)] if c.get("t") == "s" else v.text)
        el.clear()
        # se vuelven a pegar las celdas que cortó el ';'
        if celdas:
            yield ";".join(celdas.get(i, "") for i in range(max(celdas) + 1))


# saca espacios duros (había uno pegado al twitter de un catador)
def limpiar(valor):
    valor = valor.replace("\xa0", " ").strip()
    return re.sub(r"\s{2,}", " ", valor)


def main():
    with zipfile.ZipFile(ORIGEN) as libro:
        texto = "\n".join(corregir_codificacion(l) for l in leer_lineas(libro))
    filas = list(csv.reader(io.StringIO(texto)))
    encabezado, datos = filas[0], filas[1:]
    assert len(encabezado) == 14, encabezado
    malas = [f for f in datos if len(f) != 14]
    assert not malas, f"hay {len(malas)} filas mal armadas"

    DESTINO.parent.mkdir(exist_ok=True)
    with open(DESTINO, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, quoting=csv.QUOTE_MINIMAL, lineterminator="\n")
        w.writerow(COLUMNAS)
        for fila in datos:
            w.writerow([limpiar(v) for v in fila])

    # para controlar: tienen que ser 129971 filas
    restos = sum(1 for f in datos for v in f if re.search("Ã|â€|Â", v))
    print("filas:", len(datos))
    print("valores que siguen raros:", restos)


if __name__ == "__main__":
    main()
