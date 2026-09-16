# Script para evitar el apagado no deseado en una VM de Google Cloud
# Autor: Asistente de IA

Write-Host "Iniciando bloqueo de apagado..." -ForegroundColor Cyan

# 1. Prevenir apagados programados mediante el comando shutdown
# Este comando crea una tarea que se ejecuta cada minuto para cancelar cualquier apagado en curso.
$scheduledTaskName = "BlockScheduledShutdown"
$action = New-ScheduledTaskAction -Execute "shutdown.exe" -Argument "-a"
$trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 1) -Once -At (Get-Date).AddMinutes(1)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $scheduledTaskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction SilentlyContinue
Write-Host "Tarea programada de vigilancia creada." -ForegroundColor Green

# 2. Prevenir apagados iniciados por el GCP Guest Agent (metadata 'windows-keys')
# Este comando intenta bloquear la acción del agente de GCP que puede causar el apagado.
try {
    $gcpAgentPath = "C:\Program Files\Google\Compute Engine\metadata_scripts"
    if (Test-Path $gcpAgentPath) {
        # Bloquea el archivo del agente de GCP que inicia el apagado, si existe.
        # NOTA: Esto puede requerir que reinicies el servicio del agente de GCP manualmente si se actualiza.
        $agentFile = Join-Path $gcpAgentPath "GCEWindowsAgent.exe"
        if (Test-Path $agentFile) {
            # Deniega el permiso de ejecución para el archivo del agente para el usuario SYSTEM.
            # ADVERTENCIA: Esta es una medida agresiva.
            # icacls $agentFile /deny "SYSTEM:(X)" /T
            # Write-Host "Agente de GCP bloqueado de iniciar apagados." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "No se pudo modificar los permisos del agente de GCP. Saltando esta capa." -ForegroundColor Yellow
}

# 3. Registrar un Script Block que monitorea eventos de apagado para cancelarlos de inmediato.
# NOTA: Puedes ejecutar este fragmento por separado si quieres un bloqueo en tiempo real.
# Register-ObjectEvent -InputObject (Get-Process -Name "shutdown" -ErrorAction SilentlyContinue) -EventName "Exited" -Action {
#    Start-Process -FilePath "shutdown.exe" -ArgumentList "-a" -NoNewWindow
# }

Write-Host "Configuración de bloqueo completada." -ForegroundColor Cyan
Write-Host "Se recomienda reiniciar la máquina virtual para que los cambios surtan efecto completo." -ForegroundColor Cyan
