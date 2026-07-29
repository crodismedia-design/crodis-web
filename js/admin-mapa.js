(function () {
    "use strict";

    const formulario = document.getElementById("formulario-admin-taller");
    const mensaje = document.getElementById("mensaje-admin");

    if (!formulario || !mensaje || !window.supabaseClient) return;

    let tallerIdActual = null;
    let mapa = null;
    let marcador = null;
    let latitudActual = null;
    let longitudActual = null;

    function mostrar(texto, tipo = "error") {
        mensaje.textContent = texto;
        mensaje.className = `mensaje-formulario mensaje-${tipo}`;
        mensaje.hidden = false;
        mensaje.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }

    function valor(id) {
        return document.getElementById(id)?.value.trim() || "";
    }

    function cargarHojaLeaflet() {
        if (document.querySelector('link[data-tallermap-leaflet]')) return;

        const enlace = document.createElement("link");
        enlace.rel = "stylesheet";
        enlace.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
        enlace.integrity = "sha256-p4NxAoJBhIINfQ3ynhZ9JckTwvUYhNJdQMZB1z9xw=";
        enlace.crossOrigin = "";
        enlace.dataset.tallermapLeaflet = "true";
        document.head.appendChild(enlace);
    }

    function cargarLeaflet() {
        cargarHojaLeaflet();

        if (window.L) return Promise.resolve();

        return new Promise((resolve, reject) => {
            const existente = document.querySelector('script[data-tallermap-leaflet]');
            if (existente) {
                existente.addEventListener("load", resolve, { once: true });
                existente.addEventListener("error", reject, { once: true });
                return;
            }

            const script = document.createElement("script");
            script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
            script.integrity = "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=";
            script.crossOrigin = "";
            script.dataset.tallermapLeaflet = "true";
            script.addEventListener("load", resolve, { once: true });
            script.addEventListener("error", reject, { once: true });
            document.head.appendChild(script);
        });
    }

    function crearBloqueMapa() {
        if (document.getElementById("admin-bloque-mapa")) return;

        const referencia = document.getElementById("admin-provincia")?.closest(".campo-formulario");
        if (!referencia) return;

        const bloque = document.createElement("section");
        bloque.id = "admin-bloque-mapa";
        bloque.className = "campo-formulario campo-ancho";
        bloque.hidden = true;
        bloque.innerHTML = `
            <div style="display:flex;justify-content:space-between;gap:12px;align-items:center;flex-wrap:wrap">
                <div>
                    <strong>Ubicación exacta en el mapa</strong>
                    <p class="campo-ayuda" style="margin:.35rem 0 0">
                        Busca la dirección, arrastra el marcador hasta la nave correcta y guarda la ubicación.
                    </p>
                </div>
                <div style="display:flex;gap:8px;flex-wrap:wrap">
                    <button id="admin-buscar-direccion-mapa" class="boton boton-secundario boton-pequeno" type="button">
                        Buscar dirección
                    </button>
                    <button id="admin-guardar-ubicacion" class="boton boton-pequeno" type="button" disabled>
                        Guardar ubicación
                    </button>
                </div>
            </div>

            <div id="admin-mapa" style="height:420px;margin-top:14px;border-radius:12px;overflow:hidden"></div>

            <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px">
                <label>
                    <span>Latitud</span>
                    <input id="admin-latitud-mapa" type="text" readonly>
                </label>
                <label>
                    <span>Longitud</span>
                    <input id="admin-longitud-mapa" type="text" readonly>
                </label>
            </div>
        `;

        referencia.insertAdjacentElement("afterend", bloque);

        document.getElementById("admin-buscar-direccion-mapa")
            .addEventListener("click", buscarDireccion);

        document.getElementById("admin-guardar-ubicacion")
            .addEventListener("click", guardarUbicacion);
    }

    function actualizarCoordenadas(latitud, longitud) {
        latitudActual = Number(latitud);
        longitudActual = Number(longitud);

        document.getElementById("admin-latitud-mapa").value = latitudActual.toFixed(7);
        document.getElementById("admin-longitud-mapa").value = longitudActual.toFixed(7);
        document.getElementById("admin-guardar-ubicacion").disabled =
            !tallerIdActual || !Number.isFinite(latitudActual) || !Number.isFinite(longitudActual);
    }

    async function iniciarMapa(latitud = 39.4699, longitud = -0.3763, zoom = 13) {
        await cargarLeaflet();

        const contenedor = document.getElementById("admin-mapa");

        if (!mapa) {
            mapa = window.L.map(contenedor).setView([latitud, longitud], zoom);

            window.L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
                maxZoom: 20,
                attribution: "&copy; OpenStreetMap"
            }).addTo(mapa);
        } else {
            mapa.setView([latitud, longitud], zoom);
            setTimeout(() => mapa.invalidateSize(), 50);
        }

        if (marcador) {
            marcador.setLatLng([latitud, longitud]);
        } else {
            marcador = window.L.marker([latitud, longitud], {
                draggable: true
            }).addTo(mapa);

            marcador.on("dragend", () => {
                const posicion = marcador.getLatLng();
                actualizarCoordenadas(posicion.lat, posicion.lng);
            });
        }

        actualizarCoordenadas(latitud, longitud);
    }

    async function cargarUbicacionTaller() {
        if (!tallerIdActual) return;

        const bloque = document.getElementById("admin-bloque-mapa");
        bloque.hidden = false;

        const { data, error } = await window.supabaseClient
            .from("talleres")
            .select("latitud,longitud")
            .eq("id", tallerIdActual)
            .maybeSingle();

        if (error) {
            console.error("No se pudo leer la ubicación:", error);
            mostrar("No se pudo cargar la ubicación del taller.");
            return;
        }

        const latitud = Number(data?.latitud);
        const longitud = Number(data?.longitud);

        if (Number.isFinite(latitud) && Number.isFinite(longitud)) {
            await iniciarMapa(latitud, longitud, 17);
        } else {
            await iniciarMapa();
            document.getElementById("admin-guardar-ubicacion").disabled = true;
        }
    }

    async function buscarDireccion() {
        const partes = [
            valor("admin-direccion"),
            valor("admin-codigo-postal"),
            valor("admin-ciudad"),
            valor("admin-provincia"),
            "España"
        ].filter(Boolean);

        if (partes.length < 2) {
            mostrar("Escribe al menos la dirección y la población antes de buscar.");
            return;
        }

        const boton = document.getElementById("admin-buscar-direccion-mapa");
        boton.disabled = true;
        boton.textContent = "Buscando…";

        try {
            const consulta = encodeURIComponent(partes.join(", "));
            const respuesta = await fetch(
                `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&countrycodes=es&q=${consulta}`,
                { headers: { Accept: "application/json" } }
            );

            if (!respuesta.ok) throw new Error("Respuesta no válida");

            const resultados = await respuesta.json();

            if (!Array.isArray(resultados) || !resultados.length) {
                mostrar("No se encontró la dirección. Prueba escribiéndola de otra manera.", "aviso");
                return;
            }

            const latitud = Number(resultados[0].lat);
            const longitud = Number(resultados[0].lon);

            await iniciarMapa(latitud, longitud, 18);
            mostrar("Dirección localizada. Arrastra el marcador si no está exactamente sobre la nave.", "exito");
        } catch (error) {
            console.error("No se pudo localizar la dirección:", error);
            mostrar("No se pudo buscar la dirección en el mapa.");
        } finally {
            boton.disabled = false;
            boton.textContent = "Buscar dirección";
        }
    }

    async function guardarUbicacion() {
        if (!tallerIdActual) {
            mostrar("Primero guarda la ficha del taller y después corrige su ubicación.", "aviso");
            return;
        }

        if (!Number.isFinite(latitudActual) || !Number.isFinite(longitudActual)) {
            mostrar("Selecciona una ubicación válida en el mapa.");
            return;
        }

        const boton = document.getElementById("admin-guardar-ubicacion");
        boton.disabled = true;
        boton.textContent = "Guardando…";

        const { error } = await window.supabaseClient.rpc(
            "admin_guardar_ubicacion_taller",
            {
                p_taller_id: tallerIdActual,
                p_latitud: latitudActual,
                p_longitud: longitudActual
            }
        );

        boton.textContent = "Guardar ubicación";
        boton.disabled = false;

        if (error) {
            console.error("No se pudo guardar la ubicación:", error);
            mostrar("No se pudo guardar la ubicación. Comprueba que ejecutaste el SQL necesario.");
            return;
        }

        mostrar("Ubicación guardada correctamente.", "exito");
    }

    document.addEventListener("click", (evento) => {
        const editar = evento.target.closest('button[data-accion="editar"]');

        if (editar) {
            tallerIdActual = editar.closest("[data-taller-id]")?.dataset.tallerId || null;
            setTimeout(cargarUbicacionTaller, 250);
            return;
        }

        if (evento.target.closest("#boton-nuevo-taller")) {
            tallerIdActual = null;
            const bloque = document.getElementById("admin-bloque-mapa");
            if (bloque) bloque.hidden = true;
        }

        if (evento.target.closest("#boton-cancelar-editor, #boton-cancelar-admin")) {
            const bloque = document.getElementById("admin-bloque-mapa");
            if (bloque) bloque.hidden = true;
        }
    });

    crearBloqueMapa();
}());
