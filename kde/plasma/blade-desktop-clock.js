// Add the Blade clock once per desktop without moving existing instances.

var bladeClockType = "org.mysterious.bladeclock";
var bladeClockAdded = 0;
var bladeClockKept = 0;

function bladeClamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

desktops().forEach(function (desktop) {
    var existing = desktop.widgets().filter(function (widget) {
        return widget.type === bladeClockType;
    });
    if (existing.length > 0) {
        bladeClockKept += 1;
        return;
    }

    var screen = screenGeometry(desktop.screen);
    var width = bladeClamp(Math.round(screen.width * 0.18), 390, 500);
    var height = bladeClamp(Math.round(screen.height * 0.43), 540, 650);
    var x = bladeClamp(Math.round(screen.width * 0.07), 110, 260);
    var y = bladeClamp(Math.round(screen.height * 0.08), 90, 150);

    desktop.addWidget(bladeClockType, x, y, width, height);
    bladeClockAdded += 1;
});

print("Blade desktop clock: added " + bladeClockAdded
    + ", preserved " + bladeClockKept + " existing instance(s)");
