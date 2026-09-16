# Limpiar eventos anteriores si existen
Unregister-Event -SourceIdentifier "AntiShutdownTimer" -ErrorAction SilentlyContinue

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " GAY SHUTDOWN" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "Presiona CTRL+C para detener la vigilancia." -ForegroundColor Yellow
Write-Host ""

# Bucle infinito de vigilancia
while ($true) {
    # Revisamos si hay un apagado pendiente consultando el estado del sistema
    # Usamos 'shutdown /a' de forma silenciosa. Si no hay apagado, no hace nada.
    # Si hay apagado, lo cancela y devuelve un código de salida distinto.
    
    $resultado = & shutdown.exe -a 2>&1
    
    # Si el comando tuvo éxito (canceló algo), lo registramos
    if ($LASTEXITCODE -eq 0) {
        $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $mensaje = "[$fecha] ¡KOM SUSSER TOD!."
        
        # Mostrar en pantalla en rojo
        Write-Host $mensaje -ForegroundColor Red
        
        # Guardar en el archivo de log
        $mensaje | Out-File -FilePath "C:\bloqueo_apagado.log" -Append
    }
    
    # Esperamos 1 segundo antes de volver a revisar (esto es lo que hace que sea "en vivo")
    Start-Sleep -Seconds 1
}
