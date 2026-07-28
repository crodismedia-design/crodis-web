(function () {
    "use strict";

    const formulario = document.getElementById("formulario-registro");
    const campoCiudad = document.getElementById("ciudad");
    const campoCodigoPostal = document.getElementById("codigo_postal");
    const listaMunicipios = document.getElementById("municipios-supabase");
    const PREFIJOS_COMUNITAT = new Set(["03", "12", "46"]);

    let municipios = [];

    if (!formulario || !campoCiudad || !campoCodigoPostal || !listaMunicipios) {
        return;
    }

    function normalizarTexto(valor) {
        return String(valor || "")
            .normalize("NFD")
            .replace(/[\u0300-\u036f]/g, "")
            .toLocaleLowerCase("es")
            .replace(/[^a-z0-9]+/g, " ")
            .replace(/^\s*(el|la|los|las)\s+/g, "")
            .replace(/\s+/g, " ")
            .trim();
    }

    function prefijoCodigoPostal() {
        const codigoPostal = campoCodigoPostal.value.trim();
        return /^[0-9]{5}$/.test(codigoPostal) ? codigoPostal.slice(0, 2) : "";
    }

    function nombresAlternativos(nombre) {
        return [...new Set([
            nombre,
            ...String(nombre || "").split("/")
        ].map(normalizarTexto).filter(Boolean))];
    }

    function municipiosAplicables() {
        const prefijo = prefijoCodigoPostal();

        if (!PREFIJOS_COMUNITAT.has(prefijo)) {
            return prefijo ? [] : municipios;
        }

        return municipios.filter((municipio) =>
            String(municipio.codigo_municipal || "").startsWith(prefijo)
        );
    }

    function actualizarListaActiva() {
        const prefijo = prefijoCodigoPostal();
        const usarMunicipios = !prefijo || PREFIJOS_COMUNITAT.has(prefijo);

        campoCiudad.setAttribute(
            "list",
            usarMunicipios ? "municipios-supabase" : "localidades-codigo-postal"
        );
    }

    function rellenarSugerencias() {
        listaMunicipios.replaceChildren();

        municipiosAplicables().forEach((municipio) => {
            const opcion = document.createElement("option");
            opcion.value = municipio.nombre;
            opcion.label = `Código municipal ${municipio.codigo_municipal}`;
            listaMunicipios.appendChild(opcion);
        });
    }

    function buscarMunicipio(valorCiudad) {
        const prefijo = prefijoCodigoPostal();
        if (!PREFIJOS_COMUNITAT.has(prefijo)) return null;

        const ciudadNormalizada = normalizarTexto(valorCiudad);
        if (!ciudadNormalizada) return null;

        return municipiosAplicables().find((municipio) =>
            nombresAlternativos(municipio.nombre).includes(ciudadNormalizada)
        ) || null;
    }

    function validarMunicipioComunitat() {
        campoCiudad.setCustomValidity("");

        const prefijo = prefijoCodigoPostal();
        if (!PREFIJOS_COMUNITAT.has(prefijo) || !municipios.length) {
            return true;
        }

        const municipio = buscarMunicipio(campoCiudad.value);
        if (!municipio) {
            campoCiudad.setCustomValidity(
                "Selecciona una población válida de la lista de TallerMap para este código postal."
            );
            return false;
        }

        campoCiudad.value = municipio.nombre;
        return true;
    }

    async function cargarMunicipios() {
        if (!window.supabaseClient?.from) {
            console.error("No se pudo cargar la lista de municipios: Supabase no está disponible.");
            return;
        }

        const { data, error } = await window.supabaseClient
            .from("municipios")
            .select("nombre,codigo_municipal")
            .eq("activo", true)
            .order("nombre", { ascending: true });

        if (error) {
            console.error("No se pudo cargar la lista de municipios:", error);
            return;
        }

        municipios = Array.isArray(data) ? data : [];
        actualizarListaActiva();
        rellenarSugerencias();
    }

    campoCodigoPostal.addEventListener("input", () => {
        campoCiudad.setCustomValidity("");
        actualizarListaActiva();
        rellenarSugerencias();
    });

    campoCiudad.addEventListener("input", () => {
        campoCiudad.setCustomValidity("");
    });

    campoCiudad.addEventListener("blur", () => {
        const municipio = buscarMunicipio(campoCiudad.value);
        if (municipio) campoCiudad.value = municipio.nombre;
    });

    formulario.addEventListener("submit", (evento) => {
        if (validarMunicipioComunitat()) return;

        evento.preventDefault();
        evento.stopImmediatePropagation();
        campoCiudad.reportValidity();
        campoCiudad.focus();
    }, true);

    formulario.addEventListener("reset", () => {
        setTimeout(() => {
            actualizarListaActiva();
            rellenarSugerencias();
            campoCiudad.setCustomValidity("");
        }, 0);
    });

    actualizarListaActiva();
    cargarMunicipios();
}());
