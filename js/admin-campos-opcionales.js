(function () {
    "use strict";

    const formulario = document.getElementById("formulario-admin-taller");
    const mensaje = document.getElementById("mensaje-admin");
    const botonGuardar = document.getElementById("boton-guardar-admin");
    const MAXIMO_FOTOS = 5;
    const MAXIMO_BYTES_FOTO = 5 * 1024 * 1024;
    const TIPOS_FOTO = ["image/jpeg", "image/png", "image/webp"];
    let tallerIdActual = null;

    if (!formulario || !mensaje || !botonGuardar) return;

    function valor(id) {
        return document.getElementById(id)?.value.trim() || "";
    }

    function mostrar(texto, tipo = "error") {
        mensaje.textContent = texto;
        mensaje.className = `mensaje-formulario mensaje-${tipo}`;
        mensaje.hidden = false;
        mensaje.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }

    function ocultarMensaje() {
        mensaje.hidden = true;
        mensaje.textContent = "";
    }

    function normalizarWeb(web) {
        const texto = String(web || "").trim();
        if (!texto) return null;
        return /^https?:\/\//i.test(texto) ? texto : `https://${texto}`;
    }

    {
    formulario.querySelectorAll("[required]").forEach((campo) => {
        if (campo.id !== "admin-nombre") {
            campo.removeAttribute("required");
        }
    });
    }

    function marcarEtiquetaOpcional(id) {
        const etiqueta = formulario.querySelector(`label[for="${id}"]`);
        if (!etiqueta || etiqueta.querySelector(".campo-opcional")) return;
        etiqueta.childNodes.forEach((nodo) => {
            if (nodo.nodeType === Node.TEXT_NODE) {
                nodo.textContent = nodo.textContent.replace(/\s*\*\s*$/, "");
            }
        });
        const aviso = document.createElement("span");
        aviso.className = "campo-opcional";
        aviso.textContent = " (opcional para administrador)";
        etiqueta.appendChild(aviso);
    }

    function prepararAspectoFormulario() {
        hacerCamposOpcionales();
        [
            "admin-propietario", "admin-cif", "admin-email", "admin-telefono",
            "admin-direccion", "admin-codigo-postal", "admin-ciudad",
            "admin-provincia", "admin-descripcion"
        ].forEach(marcarEtiquetaOpcional);

        formulario.querySelectorAll("fieldset legend").forEach((leyenda) => {
            if (!/^(Horario semanal|Servicios)/.test(leyenda.textContent)) return;
            leyenda.textContent = leyenda.textContent.replace(/\s*\*\s*$/, "");
            if (!leyenda.textContent.includes("opcional para administrador")) {
                leyenda.textContent += " (opcional para administrador)";
            }
        });

        if (!document.getElementById("admin-aviso-campos-opcionales")) {
            const aviso = document.createElement("p");
            aviso.id = "admin-aviso-campos-opcionales";
            aviso.className = "campo-ayuda";
            aviso.textContent = "Como administrador, solo debes indicar el nombre. Puedes guardar la ficha incompleta y terminarla después.";
            formulario.prepend(aviso);
        }
    }

    function horariosOpcionales() {
        const filas = Array.from(document.querySelectorAll("#admin-lista-horarios [data-dia]"));
        if (!filas.length) return { horarios: null, error: false };

        const horarios = {};
        let hayHorario = false;

        for (const fila of filas) {
            const apertura1 = fila.querySelector('[data-turno="apertura-1"]')?.value || "";
            const cierre1 = fila.querySelector('[data-turno="cierre-1"]')?.value || "";
            const apertura2 = fila.querySelector('[data-turno="apertura-2"]')?.value || "";
            const cierre2 = fila.querySelector('[data-turno="cierre-2"]')?.value || "";

            if (!apertura1 || apertura1 === "cerrado") {
                horarios[fila.dataset.dia] = { cerrado: true, turnos: [] };
                continue;
            }

            if (!cierre1 || cierre1 <= apertura1) {
                return { horarios: null, error: true };
            }

            const turnos = [{ apertura: apertura1, cierre: cierre1 }];
            if (apertura2 || cierre2) {
                if (!apertura2 || !cierre2 || cierre2 <= apertura2 || apertura2 < cierre1) {
                    return { horarios: null, error: true };
                }
                turnos.push({ apertura: apertura2, cierre: cierre2 });
            }

            hayHorario = true;
            horarios[fila.dataset.dia] = { cerrado: false, turnos };
        }

        return { horarios: hayHorario ? horarios : null, error: false };
    }

    function serviciosSeleccionados() {
        return Array.from(
            formulario.querySelectorAll('input[name="servicios"]:checked'),
            (campo) => campo.value
        );
    }

    function fotosConservadas() {
        return Array.from(
            document.querySelectorAll("#admin-fotos-actuales input[data-foto-ruta]:checked"),
            (campo) => campo.dataset.fotoRuta
        );
    }

    function fotosOriginales() {
        return Array.from(
            document.querySelectorAll("#admin-fotos-actuales input[data-foto-ruta]"),
            (campo) => campo.dataset.fotoRuta
        );
    }

    function fotosNuevas() {
        return Array.from(document.getElementById("admin-fotos-nuevas")?.files || []);
    }

    function extensionFoto(archivo) {
        if (archivo.type === "image/png") return "png";
        if (archivo.type === "image/webp") return "webp";
        return "jpg";
    }

    function validarFotos(archivos, existentes) {
        if (archivos.length + existentes.length > MAXIMO_FOTOS) {
            mostrar(`Solo puedes conservar y añadir un máximo de ${MAXIMO_FOTOS} fotografías.`);
            return false;
        }
        if (archivos.some((archivo) => !TIPOS_FOTO.includes(archivo.type))) {
            mostrar("Las fotografías deben ser JPG, PNG o WebP.");
            return false;
        }
        if (archivos.some((archivo) => archivo.size > MAXIMO_BYTES_FOTO)) {
            mostrar("Cada fotografía puede ocupar como máximo 5 MB.");
            return false;
        }
        return true;
    }

    function parametrosEditor(fotos, horarios) {
        return {
            p_taller_id: tallerIdActual,
            p_nombre: valor("admin-nombre"),
            p_propietario: valor("admin-propietario") || null,
            p_cif: valor("admin-cif").toUpperCase() || null,
            p_email: valor("admin-email").toLowerCase() || null,
            p_telefono: valor("admin-telefono") || null,
            p_web: normalizarWeb(valor("admin-web")),
            p_direccion: valor("admin-direccion") || null,
            p_codigo_postal: valor("admin-codigo-postal") || null,
            p_ciudad: valor("admin-ciudad") || null,
            p_provincia: valor("admin-provincia") || null,
            p_horarios: horarios,
            p_servicios: serviciosSeleccionados(),
            p_fotos: fotos,
            p_descripcion: valor("admin-descripcion") || null,
            p_verificado: document.getElementById("admin-verificado")?.checked || false,
            p_activo: document.getElementById("admin-activo")?.checked ?? true
        };
    }

    function mensajeError(error) {
        const detalle = String(error?.message || "").toLowerCase();
        if (detalle.includes("could not find the function") || detalle.includes("admin_guardar_taller_opcional")) {
            return "Falta ejecutar admin_campos_opcionales.sql en Supabase.";
        }
        if (detalle.includes("no autorizado")) return "Tu sesión no tiene permisos de administración.";
        if (detalle.includes("nombre_no_valido")) return "El nombre debe contener entre 2 y 120 caracteres.";
        if (detalle.includes("documento_fiscal")) return "El CIF, NIF o NIE indicado no es válido. Puedes dejarlo vacío.";
        if (detalle.includes("email_no_valido")) return "El correo indicado no es válido. Puedes dejarlo vacío.";
        if (detalle.includes("telefono_no_valido")) return "El teléfono debe tener entre 9 y 30 caracteres o quedar vacío.";
        if (detalle.includes("web_no_valida")) return "La dirección web no es válida. Puedes dejarla vacía.";
        if (detalle.includes("direccion_no_valida")) return "La dirección debe tener entre 5 y 255 caracteres o quedar vacía.";
        if (detalle.includes("codigo_postal_no_valido")) return "El código postal debe contener cinco números o quedar vacío.";
        if (detalle.includes("provincia_codigo_postal")) return "La provincia no coincide con el código postal.";
        if (detalle.includes("ciudad_no_valida")) return "La población debe tener entre 2 y 100 caracteres o quedar vacía.";
        if (detalle.includes("horarios_no_validos")) return "Revisa los horarios o déjalos completamente cerrados.";
        if (detalle.includes("descripcion_no_valida")) return "La descripción debe tener al menos 10 caracteres o quedar vacía.";
        if (detalle.includes("duplicado")) return "Ya existe un taller con el mismo CIF o con el mismo nombre y dirección.";
        return "No se pudo guardar la ficha incompleta. Revisa la consola o la configuración de Supabase.";
    }

    async function guardarFichaOpcional(evento) {
        evento.preventDefault();
        evento.stopImmediatePropagation();
        ocultarMensaje();

        const nombre = valor("admin-nombre");
        if (nombre.length < 2 || nombre.length > 120) {
            mostrar("El nombre del taller es el único campo obligatorio y debe tener entre 2 y 120 caracteres.");
            document.getElementById("admin-nombre")?.focus();
            return;
        }

        const email = valor("admin-email");
        if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            mostrar("El correo no es válido. Corrígelo o deja el campo vacío.");
            return;
        }

        const codigoPostal = valor("admin-codigo-postal");
        if (codigoPostal && !/^\d{5}$/.test(codigoPostal)) {
            mostrar("El código postal debe contener cinco números o quedar vacío.");
            return;
        }

        const provincia = valor("admin-provincia");
        if (codigoPostal && provincia && window.TallerMapProvincias?.coincide
            && !window.TallerMapProvincias.coincide(codigoPostal, provincia)) {
            mostrar("La provincia no coincide con el código postal. Corrígela o deja ambos campos vacíos.");
            return;
        }

        const resultadoHorarios = horariosOpcionales();
        if (resultadoHorarios.error) {
            mostrar("Revisa los horarios. También puedes dejar todos los días cerrados.");
            return;
        }

        const existentes = fotosConservadas();
        const originales = fotosOriginales();
        const archivos = fotosNuevas();
        if (!validarFotos(archivos, existentes)) return;

        const nuevas = archivos.map((archivo) => ({
            archivo,
            ruta: `admin/${crypto.randomUUID()}.${extensionFoto(archivo)}`
        }));
        const fotosFinales = [...existentes, ...nuevas.map((foto) => foto.ruta)];
        const parametros = parametrosEditor(fotosFinales, resultadoHorarios.horarios);

        botonGuardar.disabled = true;
        botonGuardar.textContent = "Guardando...";

        try {
            const { data: tallerId, error } = await window.supabaseClient.rpc(
                "admin_guardar_taller_opcional",
                parametros
            );
            if (error) throw error;

            const subidasCorrectas = [];
            for (const foto of nuevas) {
                const { error: errorFoto } = await window.supabaseClient.storage
                    .from("fotos-talleres")
                    .upload(foto.ruta, foto.archivo, {
                        cacheControl: "3600",
                        contentType: foto.archivo.type,
                        upsert: false
                    });
                if (!errorFoto) subidasCorrectas.push(foto.ruta);
                else console.error("No se pudo subir una fotografía:", errorFoto);
            }

            if (subidasCorrectas.length !== nuevas.length) {
                await window.supabaseClient.rpc("admin_guardar_taller_opcional", {
                    ...parametros,
                    p_taller_id: tallerId,
                    p_fotos: [...existentes, ...subidasCorrectas]
                });
            }

            const eliminadas = originales.filter((ruta) => !existentes.includes(ruta));
            if (eliminadas.length) {
                const { error: errorBorrado } = await window.supabaseClient.storage
                    .from("fotos-talleres")
                    .remove(eliminadas);
                if (errorBorrado) console.error("No se pudieron borrar algunas fotografías:", errorBorrado);
            }

            document.getElementById("boton-cancelar-admin")?.click();
            mostrar(
                subidasCorrectas.length === nuevas.length
                    ? "Ficha guardada. Puedes completar los campos pendientes más adelante."
                    : "Ficha guardada, pero alguna fotografía no pudo subirse.",
                subidasCorrectas.length === nuevas.length ? "exito" : "aviso"
            );
            document.getElementById("boton-recargar")?.click();
            document.getElementById("boton-recargar-historial")?.click();
            tallerIdActual = null;
        } catch (error) {
            console.error("No se pudo guardar la ficha opcional:", error);
            mostrar(mensajeError(error));
        } finally {
            botonGuardar.disabled = false;
            botonGuardar.textContent = "Guardar ficha";
        }
    }

    document.addEventListener("click", (evento) => {
        const editar = evento.target.closest('button[data-accion="editar"]');
        if (editar) {
            tallerIdActual = editar.closest("[data-taller-id]")?.dataset.tallerId || null;
            return;
        }
        if (evento.target.closest("#boton-nuevo-taller")
            || evento.target.closest('[data-accion-candidato="importar"]')) {
            tallerIdActual = null;
        }
    }, true);

    const observador = new MutationObserver(hacerCamposOpcionales);
    observador.observe(formulario, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ["required"]
    });

    formulario.addEventListener("submit", guardarFichaOpcional, true);
    prepararAspectoFormulario();
}());
