# Lab 8 czesc A: wersja 1 -> wersja 2 -> rollback do wersji 1 (Kubernetes w Docker Desktop)
$out = "dowody\lab8-k8s.txt"
$v2 = "zlecenia-rules-daniel:9f6ea68"   # commit 9f6ea68, wersja 2.0.1
$url = "http://localhost:30080"
$body = '{"sku":"SKU-A","quantity":6}'
$pods = "kubectl get pods -l app=zlecenia-rules -o custom-columns=POD:.metadata.name,OBRAZ:.spec.containers[0].image,STAN:.status.phase"
New-Item -ItemType Directory -Force dowody | Out-Null
Remove-Item $out -ErrorAction SilentlyContinue

function Log($text) { Write-Host $text; Add-Content -Path $out -Value $text -Encoding UTF8 }
function Run($cmd) {
    Log "> $cmd"
    $res = (Invoke-Expression "$cmd 2>&1" | ForEach-Object { "$_" }) -join "`n"
    Log "$res`n"
}
function Call($label) {
    Start-Sleep -Seconds 3
    Log "> POST $url/decide $body   ($label)"
    try {
        $r = Invoke-RestMethod -Method Post -Uri "$url/decide" -ContentType "application/json" -Body $body
        Log (($r | ConvertTo-Json -Compress) + "`n")
    } catch { Log "BLAD: $($_.Exception.Message)`n" }
}

Log "=== 0. Aktywny kontekst i wezly klastra ==="
Run "kubectl config current-context"
Run "kubectl get nodes"

Log "=== 1. Obrazy dostepne lokalnie (zbudowane z commitow 2804f97 i 9f6ea68) ==="
Run "docker images zlecenia-rules-daniel --format '{{.Repository}}:{{.Tag}}  {{.ID}}'"

Log "=== 2. Wersja 1: obraz 2804f97 (2.0.0) ==="
Run "kubectl apply -f k8s/"
Run "kubectl rollout status deployment/zlecenia-rules --timeout=120s"
Run $pods
Call "wersja 1"

Log "=== 3. Aktualizacja do wersji 2: obraz 9f6ea68 (2.0.1) ==="
Run "kubectl set image deployment/zlecenia-rules reguly=$v2"
Run "kubectl annotate deployment/zlecenia-rules kubernetes.io/change-cause='obraz 9f6ea68 (2.0.1)' --overwrite"
Run "kubectl rollout status deployment/zlecenia-rules --timeout=120s"
Run $pods
Call "wersja 2"

Log "=== 4. Rollback do poprzedniej rewizji ==="
Run "kubectl rollout undo deployment/zlecenia-rules"
Run "kubectl rollout status deployment/zlecenia-rules --timeout=120s"
Run "kubectl rollout history deployment/zlecenia-rules"
Call "po rollbacku"

Log "=== 5. Stan koncowy (po 40 s, gdy stare pody sa juz wylaczone) ==="
Start-Sleep -Seconds 40
Run $pods

Log "Zapisano: $out"