* ============================================================
* T5 — Do-file automatizado de análisis de ingresos
* Autor: Javier Ignacio Cáceres Venegas      
* ============================================================
version 18
clear all
set more off
capture mkdir "output"
capture log close
log using "output/tarea_t5.log", replace text
* ------------------------------------------------------------
* 1. Encabezado con macros de configuración
* ------------------------------------------------------------
* Se usa local para parámetros propios de este do-file, 
* evitando colisiones en otros scripts.
* Se usa global para parámetros que podrían compartirse entre
* distintos do-files
local datos     "data/raw/casen_reducido.csv"
local depvar    "ingreso"
local numericas "ingreso educ edad experiencia"
local controles "educ experiencia"
local grupos    "sector region genero"
global umbral   = 500000
* ------------------------------------------------------------
* 2. Carga y preparación de datos
* ------------------------------------------------------------
import delimited "`datos'", clear varnames(1) encoding("utf-8")

* Experiencia potencial de Mincer (no se incluye 'edad' en controles
* junto a 'educ' y 'experiencia' para evitar colinealidad exacta)
generate experiencia = max(edad - educ - 6, 0)
label variable experiencia "Experiencia potencial (años)"

* Variable indicadora 0/1 con etiquetas de valores para el sexo
* genero' es string y no puede usarse directamente como factor i.genero
generate mujer = .
replace mujer = 1 if genero == "F"
replace mujer = 0 if genero == "M"
label define lb_mujer 0 "Hombre (M)" 1 "Mujer (F)", replace
label values mujer lb_mujer
label variable mujer "Indicadora de mujer (1 = F, 0 = M)"

* ------------------------------------------------------------
* 3. Loop foreach sobre lista de variables numéricas
* ------------------------------------------------------------
foreach v of local numericas {
    display _newline "--- Estadísticos detallados: `v' ---"
    summarize `v', detail
}

* ------------------------------------------------------------
* 4. Loop forvalues con rango (tramos de educación)
* ------------------------------------------------------------
* Evalúa tramos de 4 años desde 4 hasta 19 (4-7, 8-11, 12-15, 16-19)
forvalues t = 4(4)16 {
    local sup = `t' + 3
    quietly count if educ >= `t' & educ <= `sup'
    display "Educación de `t' a `sup' años: " r(N) " personas"
}

* ------------------------------------------------------------
* 5. Programa reutilizable con argumentos llamado desde un loop
* ------------------------------------------------------------
capture program drop descriptivos_grupo
program define descriptivos_grupo
    args var_grupo
    display _newline "=== Descriptivos por `var_grupo' ==="
    tabulate `var_grupo', missing
    tabstat ingreso educ, by(`var_grupo') statistics(mean sd n) nototal
end

foreach g of local grupos {
    descriptivos_grupo `g'
}

* ------------------------------------------------------------
* 6. Uso de variable temporal (tempvar)
* ------------------------------------------------------------
* tempvar le crea un nombre unico a la variable, asi nos evitamos sobreescribir
* variables existentes y luego la elimina.
tempvar ing_miles
generate `ing_miles' = `depvar' / 1000
label variable `ing_miles' "Ingreso en miles de pesos"
summarize `ing_miles'

* ------------------------------------------------------------
* 7. Manejo explícito de valores faltantes (missing)
* ------------------------------------------------------------
* Para que stata no trate a los valores faltantes como mayores a cualquier numero
*finito e infle erroneamente los datos.
count if `depvar' > $umbral & !missing(`depvar')
display "Personas con `depvar' > " $umbral " (excluyendo missing): " r(N)

* ------------------------------------------------------------
* 8. Modelos guardados y comparados
* ------------------------------------------------------------
estimates drop _all
quietly regress `depvar' `controles'
estimates store m1

quietly regress `depvar' `controles' i.mujer
estimates store m2

estimates table m1 m2, b(%9.0f) se stats(N r2) stfmt(%5.3f)

* Mostrar coeficiente de educación de m2 usando _b[educ]
estimates restore m2
display "Coeficiente de educ en m2 (en pesos): " %9.2f _b[educ]
* ------------------------------------------------------------
* 9. Regresión por sector en matriz J() y exportada a Excel
* ------------------------------------------------------------
levelsof sector, local(sectores)
local n_sec : word count `sectores'

* Matriz con n_sec filas y 3 columnas: [coef_educ, se_educ, N]
matrix res_sector = J(`n_sec', 3, .)
matrix colnames res_sector = coef_educ se_educ N

local fila = 1
foreach s of local sectores {
    quietly regress `depvar' educ if sector == "`s'"
    matrix res_sector[`fila', 1] = _b[educ]
    matrix res_sector[`fila', 2] = _se[educ]
    matrix res_sector[`fila', 3] = e(N)
    local fila = `fila' + 1
}

matrix list res_sector

putexcel set "output/tarea_t5_por_sector.xlsx", replace
putexcel A1 = "sector" B1 = "coef_educ" C1 = "se_educ" D1 = "n"

local fila_xls = 2
local idx = 1
foreach s of local sectores {
    putexcel A`fila_xls' = "`s'"
    putexcel B`fila_xls' = matrix(res_sector[`idx', 1]), nformat("#,##0.00")
    putexcel C`fila_xls' = matrix(res_sector[`idx', 2]), nformat("#,##0.00")
    putexcel D`fila_xls' = matrix(res_sector[`idx', 3]), nformat("#,##0")
    local fila_xls = `fila_xls' + 1
    local idx = `idx' + 1
}

* ------------------------------------------------------------
* 10. Cierre de bitácora e interpretación
* ------------------------------------------------------------
log close

*Intepretación: 

*Cada año extra de estudio se asocia con unos $42.250 más en el ingreso promedio, *controlando por experiencia y sexo, sin que esto signifique una relación de causa y *efecto. Al sumar la variable de mujer, el modelo explica un poco más la variación de *los ingresos y ajusta el efecto. En los análisis por sector hay pocos casos en cada *grupo, por lo que los resultados son menos precisos y varían bastante. Además, faltan *datos de ingreso en algunas personas y no se consideran factores importantes como las* *horas trabajadas o el tipo de empleo. En resumen, muestran tendencias útiles de la *muestra, pero con límites claros.