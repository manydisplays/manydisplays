# ManyDisplays

App de barra de menús (sin icono en el Dock) que guarda **en tiempo casi real** dónde está
cada ventana —monitor, posición, tamaño y escritorio— y las devuelve a su sitio
automáticamente cuando el Mac vuelve del reposo o del bloqueo, o cuando reconectas
los monitores.

## Por qué existe (lo que se investigó)

- macOS identifica cada monitor por los datos de su EDID (fabricante, modelo, número de serie
  y fecha de fabricación). Cuando dos monitores idénticos dan el mismo serial (muchos
  envían `0` o `0x01010101`), macOS no puede distinguirlos y al despertar reparte la
  disposición y las ventanas al azar. **A octubre de 2026, Apple sigue sin resolverlo**: hay
  hilos abiertos en los foros de desarrolladores con macOS 26 (Tahoe) y monitores idénticos.
- En tu caso los dos **LG HDR 4K sí tienen seriales distintos** (`415816` y `333443`, fabricados
  en años diferentes), así que se pueden distinguir de forma fiable. El desorden viene sobre
  todo de que, al dormir o bloquear, los monitores DisplayPort/Thunderbolt se "desconectan";
  macOS amontona las ventanas en el que vuelve primero y no las devuelve a su sitio.
- Stay falla al "guardar" con muchas ventanas porque pregunta una a una a cada app por
  Accesibilidad (lento, y se cuelga si una app no responde). ManyDisplays guarda leyendo la
  lista de ventanas del servidor de ventanas: ~20 ms para cientos de ventanas, sin preguntar
  a ninguna app.

## Cómo funciona

| Situación | Qué hace |
|---|---|
| Mueves o redimensionas una ventana, o abres/cierras una | Guarda en ~1,5 s (por eventos, sin polling) + comprobación ligera cada 20 s |
| Bloqueo, reposo, pantallas en reposo, monitores reconectándose | Toma una última foto y **congela** el guardado para no grabar el desorden |
| Vuelves (desbloqueo / despertar) y los monitores llevan unos segundos estables | Restaura: cada ventana vuelve a **su monitor físico** (por número de serie), posición y tamaño. Hace 3 pasadas porque macOS sigue moviendo ventanas un rato |
| macOS intercambió la disposición de los monitores (izq ↔ der o el principal) | La vuelve a poner como estaba (desactivable en el menú) |
| Solo con la MacBook, sin monitores externos | **Inactiva**: sin observadores ni temporizadores |
| Cerraste ventanas mientras trabajabas solo con la MacBook | No se reabren: solo se mueven ventanas que siguen existiendo; las cerradas se olvidan |
| Ventanas nuevas abiertas mientras tanto | No se tocan; desde ese momento se siguen |

Se guarda un layout **por cada combinación de monitores** (identificados por fabricante, modelo
y serial; si un día hubiese seriales repetidos, se desempata por UUID y luego por posición). Si
cambias la resolución, las posiciones se escalan proporcionalmente.

Datos: `~/Library/Application Support/ManyDisplays/layouts.json` · Registro: `~/Library/Logs/ManyDisplays.log`

## Instalar

```bash
scripts/build-app.sh --install   # compila, firma, copia a /Applications y la abre
```

La primera vez pide **Accesibilidad** (Ajustes del Sistema → Privacidad y seguridad →
Accesibilidad → ManyDisplays). Sin ese permiso guarda posiciones igualmente, pero no puede
mover ventanas. Se firma con tu certificado "Apple Development" para que el permiso no se
pierda al recompilar. Activa "Abrir al iniciar sesión" desde el menú.

## Atajos

- `⌃⌥⌘R` restaurar ahora · `⌃⌥⌘S` guardar ahora (normalmente no hace falta ninguno)
- Desde terminal / Atajos / Raycast: `/Applications/ManyDisplays.app/Contents/MacOS/ManyDisplays --restore` (o `--save`)
- Diagnóstico: `.../ManyDisplays --dump` muestra monitores, escritorios, ventanas y qué movería una restauración

## Límite conocido: escritorios (Spaces)

Desde macOS 14.5 Apple bloqueó mover ventanas **de otras apps** entre escritorios sin
desactivar SIP. Se comprobó en tu macOS 26.6 con los tres métodos privados conocidos
(`CGSMoveWindowsToManagedSpace`, `SetWindowListWorkspace` con compat ID y
`Add/RemoveWindowsFromSpaces`): ninguno funciona. En la práctica no suele importar: con
"Las pantallas tienen Spaces separados" desactivado (tu configuración) el reposo no cambia
de escritorio a las ventanas, solo las desordena entre monitores. Si alguna ventana acaba en
otro escritorio, el menú lo indica.

Las ventanas de otros escritorios se recolocan sin tener que visitarlos. Si una app se resiste,
la ventana queda pendiente y se coloca al entrar en su escritorio.
