(function () {
    "use strict";

    const acceso = document.getElementById("acceso-propietario");
    const panel = document.getElementById("panel-propietario");
    const formulario = document.getElementById("formulario-edicion");
    const sinTalleres = document.getElementById("sin-talleres");
    const mensajeAcceso = document.getElementById("mensaje-acceso");
    const mensajeEdicion = document.getElementById("mensaje-edicion");
    const botonAcceso = document.getElementById("boton-acceso");
    const botonGuardar = document.getElementById("boton-guardar");
    const selectorTaller = document.getElementById("selector-taller");
    const listaHorarios = document.getElementById("lista-horarios-edicion");
    const DIAS = [
        ["lunes", "Lunes"], ["martes", "Martes"], ["miercoles", "Miércoles"],
        ["jueves", "Jueves"], ["viernes", "Viernes"], ["sabado", "Sábado"],
        ["domingo", "Domingo"]
    ];
    const localidadesPorCodigo = new Map();
    let talleres = [];
    let tallerActual = null;

    function mostrarMensaje(elemento, texto, tipo) {
        if (!elemento) return;
        elemento.textContent = texto;
        elemento.className = `mensaje-formulario mensaje-${tipo}`;
        elemento.hidden = false;
    }

    function ocultarMensaje(elemento) {
        if (!elemento) return;
        elemento.hidden = true;
        elemento.textContent = "";
        elemento.className = "mensaje-formulario";
    }

    function valor(id) {
        return document.getElementById(id)?.value.trim() || "";
    }

    function normalizarWeb(web) {
        const texto = String(web || "").trim();
        if (!texto) return "";
        return /^https?:\/\//i.test(texto) ? texto : `https://${texto}`;
    }

    function normalizarTexto(texto) {
        return String(texto || "")
            .normalize("NFD")
            .replace(/[\u0300-\u036f]/g, "")
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, " ")
            .trim();
    }

    async function consultarLocalidades(codigoPostal) {
        if (localidadesPorCodigo.has(codigoPostal)) {
            return localidadesPorCodigo.get(codigoPostal);
        }
        const controlador = new AbortController();
        const limite = setTimeout(() => controlador.abort(), 9000);
        try {
            const respuesta = await fetch(
                `https://api.zippopotam.us/ES/${encodeURIComponent(codigoPostal)}`,
                { headers: { Accept: "application/json" }, signal: controlador.signal }
            );
            if (respuesta.status === 404) {
                localidadesPorCodigo.set(codigoPostal, []);
                return [];
            }
            if (!respuesta.ok) throw new Error(`postal-${respuesta.status}`);
            const datos = await respuesta.json();
            const localidades = [...new Set((datos.places || [])
                .map((lugar) => String(lugar["place name"] || "").trim())
                .filter(Boolean))];
            localidadesPorCodigo.set(codigoPostal, localidades);
            return localidades;
        } finally {
            clearTimeout(limite);
        }
    }

    function rellenarLocalidades(localidades) {
        const lista = document.getElementById("localidades-edicion");
        lista.replaceChildren();
        localidades.forEach((localidad) => {
            const opcion = document.createElement("option");
            opcion.value = localidad;
            lista.appendChild(opcion);
        });
    }

    async function comprobarLocalidad(completar = false) {
        const codigoPostal = valor("codigo-postal");
        const estado = document.getElementById("estado-codigo-postal");
        if (!/^[0-9]{5}$/.test(codigoPostal)) return null;
        estado.textContent = "Comprobando código postal y población…";
        estado.className = "campo-estado campo-estado-cargando";
        try {
            const localidades = await consultarLocalidades(codigoPostal);
            rellenarLocalidades(localidades);
            if (!localidades.length) {
                estado.textContent = "No encontramos ese código postal en España.";
                estado.className = "campo-estado campo-estado-error";
                return [];
            }
            if (completar && !valor("ciudad")) {
                document.getElementById("ciudad").value = localidades[0];
            }
            estado.textContent = localidades.length === 1
                ? `✓ Código postal correspondiente a ${localidades[0]}.`
                : `✓ Poblaciones admitidas: ${localidades.join(", ")}.`;
            estado.className = "campo-estado campo-estado-exito";
            return localidades;
        } catch (error) {
            console.error("No se pudo comprobar el código postal:", error);
            estado.textContent = "No se pudo comprobar ahora la población. Inténtalo de nuevo.";
            estado.className = "campo-estado campo-estado-error";
            return null;
        }
    }

    async function localidadCoincide() {
        const localidades = await comprobarLocalidad(false);
        const ciudad = valor("ciudad");
        if (!localidades?.length) return false;
        const ciudadNormalizada = normalizarTexto(ciudad);
        return localidades.some((localidad) => {
            const localidadNormalizada = normalizarTexto(localidad);
            return ciudadNormalizada === localidadNormalizada
                || ciudadNormalizada.includes(localidadNormalizada)
                || localidadNormalizada.includes(ciudadNormalizada);
        });
    }

    function opcionesHoras(incluirCerrado = false, incluirVacio = false) {
        const opciones = [];
        if (incluirVacio) opciones.push('<option value="">Sin segundo turno</option>');
        else opciones.push('<option value="">Elige…</option>');
        if (incluirCerrado) opciones.push('<option value="cerrado">Cerrado</option>');
        for (let hora = 0; hora < 24; hora += 1) {
            for (const minutos of ["00", "30"]) {
                const texto = `${String(hora).padStart(2, "0")}:${minutos}`;
                opciones.push(`<option value="${texto}">${texto}</option>`);
            }
        }
        if (!incluirCerrado) opciones.push('<option value="24:00">24:00</option>');
        return opciones.join("");
    }

    function crearHorarios() {
        listaHorarios.innerHTML = DIAS.map(([clave, etiqueta]) => `
            <div class="horario-fila" data-dia="${clave}">
                <strong>${etiqueta}</strong>
                <label><span>Apertura</span><select data-turno="apertura-1" aria-label="Apertura del ${etiqueta}" required>${opcionesHoras(true)}</select></label>
                <label><span>Cierre</span><select data-turno="cierre-1" aria-label="Cierre del ${etiqueta}" disabled>${opcionesHoras()}</select></label>
                <label><span>Segunda apertura</span><select data-turno="apertura-2" aria-label="Segunda apertura del ${etiqueta}" disabled>${opcionesHoras(false, true)}</select></label>
                <label><span>Segundo cierre</span><select data-turno="cierre-2" aria-label="Segundo cierre del ${etiqueta}" disabled>${opcionesHoras(false, true)}</select></label>
            </div>
        `).join("");
    }

    function actualizarFila(fila) {
        const apertura1 = fila.querySelector('[data-turno="apertura-1"]');
        const cierre1 = fila.querySelector('[data-turno="cierre-1"]');
        const apertura2 = fila.querySelector('[data-turno="apertura-2"]');
        const cierre2 = fila.querySelector('[data-turno="cierre-2"]');
        const cerrado = !apertura1.value || apertura1.value === "cerrado";
        cierre1.disabled = cerrado;
        cierre1.required = !cerrado;
        apertura2.disabled = cerrado;
        if (cerrado) {
            cierre1.value = "";
            apertura2.value = "";
            cierre2.value = "";
            cierre2.disabled = true;
            cierre2.required = false;
            return;
        }
        cierre2.disabled = !apertura2.value;
        cierre2.required = Boolean(apertura2.value);
        if (!apertura2.value) cierre2.value = "";
    }

    function leerHorarios() {
        const horarios = {};
        listaHorarios.querySelectorAll("[data-dia]").forEach((fila) => {
            const apertura1 = fila.querySelector('[data-turno="apertura-1"]').value;
            const cierre1 = fila.querySelector('[data-turno="cierre-1"]').value;
            const apertura2 = fila.querySelector('[data-turno="apertura-2"]').value;
            const cierre2 = fila.querySelector('[data-turno="cierre-2"]').value;
            horarios[fila.dataset.dia] = apertura1 === "cerrado"
                ? { cerrado: true, turnos: [] }
                : {
                    cerrado: false,
                    turnos: [
                        { apertura: apertura1, cierre: cierre1 },
                        ...(apertura2 ? [{ apertura: apertura2, cierre: cierre2 }] : [])
                    ]
                };
        });
        return horarios;
    }

    function validarHorarios(horarios) {
        if (Object.keys(horarios).length !== 7) return false;
        let hayDiaAbierto = false;
        for (const horario of Object.values(horarios)) {
            if (horario.cerrado) continue;
            hayDiaAbierto = true;
            if (!horario.turnos.length) return false;
            for (let indice = 0; indice < horario.turnos.length; indice += 1) {
                const turno = horario.turnos[indice];
                if (!turno.apertura || !turno.cierre || turno.cierre <= turno.apertura) return false;
                if (indice === 1 && turno.apertura < horario.turnos[0].cierre) return false;
            }
        }
        return hayDiaAbierto;
    }

    function cargarHorarios(horarios) {
        const horarioValido = horarios && typeof horarios === "object";
        listaHorarios.querySelectorAll("[data-dia]").forEach((fila) => {
            const horario = horarioValido ? horarios[fila.dataset.dia] : null;
            const turnos = horario?.turnos || [];
            fila.querySelector('[data-turno="apertura-1"]').value =
                horario?.cerrado ? "cerrado" : (turnos[0]?.apertura || "");
            actualizarFila(fila);
            fila.querySelector('[data-turno="cierre-1"]').value = turnos[0]?.cierre || "";
            fila.querySelector('[data-turno="apertura-2"]').value = turnos[1]?.apertura || "";
            actualizarFila(fila);
            fila.querySelector('[data-turno="cierre-2"]').value = turnos[1]?.cierre || "";
        });
    }

    function serviciosSeleccionados() {
        return Array.from(
            formulario.querySelectorAll('input[name="servicios"]:checked'),
            (campo) => campo.value
        );
    }

    function cargarServicios(servicios) {
        const elegidos = new Set(Array.isArray(servicios) ? servicios : []);
        formulario.querySelectorAll('input[name="servicios"]').forEach((campo) => {
            campo.checked = elegidos.has(campo.value);
        });
    }

    function cargarTaller(taller) {
        tallerActual = taller;
        document.getElementById("nombre").value = taller.nombre || "";
        document.getElementById("propietario").value = taller.propietario || "";
        document.getElementById("telefono").value = taller.telefono || "";
        document.getElementById("cif-protegido").value = taller.cif || "";
        document.getElementById("email-protegido").value = taller.email || "";
        document.getElementById("web").value = taller.web || "";
        document.getElementById("direccion").value = taller.direccion || "";
        document.getElementById("codigo-postal").value = taller.codigo_postal || "";
        document.getElementById("ciudad").value = taller.ciudad || "";
        document.getElementById("provincia-edicion").value = taller.provincia || "";
        document.getElementById("descripcion").value = taller.descripcion || "";
        cargarHorarios(taller.horarios);
        cargarServicios(taller.servicios);
        ocultarMensaje(mensajeEdicion);
    }

    function mostrarEditor() {
        sinTalleres.hidden = talleres.length > 0;
        formulario.hidden = talleres.length === 0;
        const grupoSelector = document.getElementById("grupo-selector-taller");
        grupoSelector.hidden = talleres.length < 2;
        selectorTaller.replaceChildren();
        talleres.forEach((taller) => {
            const opcion = document.createElement("option");
            opcion.value = taller.id;
            opcion.textContent = `${taller.nombre} — ${taller.ciudad || "sin población"}`;
            selectorTaller.appendChild(opcion);
        });
        if (talleres.length) cargarTaller(talleres[0]);
    }

    async function cargarMisTalleres() {
        ocultarMensaje(mensajeEdicion);
        const { data, error } = await window.supabaseClient.rpc("mis_talleres");
        if (error) {
            console.error("No se pudieron cargar los talleres del propietario:", error);
            const detalle = String(error.message || "").toLowerCase();
            mostrarMensaje(
                mensajeEdicion,
                detalle.includes("mis_talleres")
                    ? "Falta activar la edición de propietarios en Supabase."
                    : "No se pudieron cargar tus talleres. Inténtalo de nuevo.",
                "error"
            );
            return;
        }
        talleres = data || [];
        mostrarEditor();
    }

    async function mostrarSesion(session) {
        acceso.hidden = true;
        panel.hidden = false;
        document.getElementById("email-sesion").textContent = session.user.email || "";
        await cargarMisTalleres();
    }

    function mostrarAcceso() {
        acceso.hidden = false;
        panel.hidden = true;
        formulario.hidden = true;
        sinTalleres.hidden = true;
        talleres = [];
        tallerActual = null;
    }

    async function enviarEnlace() {
        const email = valor("email-acceso").toLowerCase();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            mostrarMensaje(mensajeAcceso, "Escribe un correo electrónico válido.", "error");
            return;
        }
        botonAcceso.disabled = true;
        botonAcceso.textContent = "Enviando enlace...";
        ocultarMensaje(mensajeAcceso);
        const redirectTo = `${window.location.origin}/pages/mi-taller.html`;
        const { error } = await window.supabaseClient.auth.signInWithOtp({
            email,
            options: { emailRedirectTo: redirectTo, shouldCreateUser: false }
        });
        botonAcceso.disabled = false;
        botonAcceso.textContent = "Recibir enlace de acceso";
        if (error) {
            console.error("No se pudo enviar el enlace de gestión:", error);
            mostrarMensaje(
                mensajeAcceso,
                "No se pudo enviar el enlace. Comprueba que usas el correo con el que publicaste el taller.",
                "error"
            );
            return;
        }
        mostrarMensaje(
            mensajeAcceso,
            "Enlace enviado. Abre tu correo y pulsa el enlace para gestionar tu taller.",
            "exito"
        );
    }

    function mensajeError(error) {
        const detalle = String(error?.message || "").toLowerCase();
        if (detalle.includes("taller_no_autorizado")) return "No tienes permiso para modificar este taller.";
        if (detalle.includes("provincia_codigo_postal")) return "La provincia no coincide con el código postal.";
        if (detalle.includes("horarios")) return "Revisa los horarios. Debe existir al menos un día abierto.";
        if (detalle.includes("servicios")) return "Selecciona al menos un servicio.";
        if (detalle.includes("web")) return "La dirección de la página web no es válida.";
        if (detalle.includes("sesion")) return "La sesión ha caducado. Solicita otro enlace de acceso.";
        return "No se pudieron guardar los cambios. Revisa los datos e inténtalo de nuevo.";
    }

    async function guardarCambios(evento) {
        evento.preventDefault();
        ocultarMensaje(mensajeEdicion);
        if (!tallerActual) return;
        if (!formulario.checkValidity()) {
            formulario.reportValidity();
            return;
        }

        const codigoPostal = valor("codigo-postal");
        const provincia = valor("provincia-edicion");
        if (!window.TallerMapProvincias?.coincide(codigoPostal, provincia)) {
            mostrarMensaje(mensajeEdicion, "La provincia no coincide con el código postal.", "error");
            return;
        }
        if (!await localidadCoincide()) {
            mostrarMensaje(
                mensajeEdicion,
                `La población indicada no coincide con el código postal ${codigoPostal}.`,
                "error"
            );
            return;
        }
        const horarios = leerHorarios();
        if (!validarHorarios(horarios)) {
            mostrarMensaje(
                mensajeEdicion,
                "Selecciona un horario válido o «Cerrado» para todos los días y deja al menos un día abierto.",
                "error"
            );
            return;
        }
        const servicios = serviciosSeleccionados();
        if (!servicios.length) {
            mostrarMensaje(mensajeEdicion, "Selecciona al menos un servicio.", "error");
            return;
        }

        botonGuardar.disabled = true;
        botonGuardar.textContent = "Guardando cambios...";
        const { error } = await window.supabaseClient.rpc("actualizar_mi_taller", {
            p_taller_id: tallerActual.id,
            p_nombre: valor("nombre"),
            p_propietario: valor("propietario"),
            p_telefono: valor("telefono"),
            p_web: normalizarWeb(valor("web")) || null,
            p_direccion: valor("direccion"),
            p_codigo_postal: codigoPostal,
            p_ciudad: valor("ciudad"),
            p_provincia: provincia,
            p_horarios: horarios,
            p_servicios: servicios,
            p_descripcion: valor("descripcion")
        });
        botonGuardar.disabled = false;
        botonGuardar.textContent = "Guardar cambios";

        if (error) {
            console.error("No se pudo actualizar el taller:", error);
            mostrarMensaje(mensajeEdicion, mensajeError(error), "error");
            return;
        }
        await cargarMisTalleres();
        mostrarMensaje(
            mensajeEdicion,
            "Cambios guardados correctamente. La ficha pública ya está actualizada.",
            "exito"
        );
        mensajeEdicion.scrollIntoView({ behavior: "smooth", block: "center" });
    }

    function copiarLunes() {
        const filas = Array.from(listaHorarios.querySelectorAll("[data-dia]"));
        const origen = filas[0];
        if (!origen) return;
        const valores = Array.from(origen.querySelectorAll("select"), (select) => select.value);
        filas.slice(1, 5).forEach((fila) => {
            fila.querySelectorAll("select").forEach((select, indice) => {
                select.value = valores[indice] || "";
            });
            actualizarFila(fila);
            fila.querySelectorAll("select").forEach((select, indice) => {
                select.value = valores[indice] || "";
            });
        });
    }

    function cerrarFinSemana() {
        ["sabado", "domingo"].forEach((dia) => {
            const fila = listaHorarios.querySelector(`[data-dia="${dia}"]`);
            if (!fila) return;
            fila.querySelector('[data-turno="apertura-1"]').value = "cerrado";
            actualizarFila(fila);
        });
    }

    crearHorarios();
    window.TallerMapServicios?.rellenarCheckboxes(
        document.getElementById("lista-servicios-edicion")
    );
    window.TallerMapProvincias?.rellenarSelect(
        document.getElementById("provincia-edicion")
    );

    listaHorarios.addEventListener("change", (evento) => {
        const fila = evento.target.closest("[data-dia]");
        if (fila) actualizarFila(fila);
    });
    document.getElementById("codigo-postal").addEventListener("input", async (evento) => {
        const codigo = evento.target.value.replace(/\D/g, "").slice(0, 5);
        evento.target.value = codigo;
        const provincia = window.TallerMapProvincias?.seleccionarSegunCodigo(
            codigo,
            document.getElementById("provincia-edicion")
        );
        const estado = document.getElementById("estado-codigo-postal");
        estado.textContent = provincia
            ? `Código postal correspondiente a ${provincia.nombre}.`
            : "Debe coincidir con los dos primeros dígitos del código postal.";
        estado.className = provincia ? "campo-estado campo-estado-exito" : "campo-estado";
        if (provincia) await comprobarLocalidad(true);
    });
    selectorTaller.addEventListener("change", () => {
        const taller = talleres.find((item) => item.id === selectorTaller.value);
        if (taller) cargarTaller(taller);
    });
    botonAcceso.addEventListener("click", enviarEnlace);
    formulario.addEventListener("submit", guardarCambios);
    document.getElementById("copiar-horario-edicion").addEventListener("click", copiarLunes);
    document.getElementById("cerrar-fin-semana-edicion").addEventListener("click", cerrarFinSemana);
    document.getElementById("boton-cerrar-sesion").addEventListener("click", async () => {
        await window.supabaseClient.auth.signOut();
        mostrarAcceso();
    });

    window.supabaseClient.auth.onAuthStateChange((_evento, session) => {
        if (session) mostrarSesion(session);
        else mostrarAcceso();
    });

    window.supabaseClient.auth.getSession().then(({ data }) => {
        if (data.session) mostrarSesion(data.session);
        else mostrarAcceso();
    });
}());
