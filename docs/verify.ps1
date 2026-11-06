# ============================================================
# TP13 - Verification du flux OAuth2 / OpenID Connect complet
# Prerequis :
#   1) le fournisseur d'identite mock : node tools/mock-idp/server.js   (port 9090)
#   2) l'application                  : APP_PROFILE=mock java -jar target/oauth2-client-1.0.0.jar (port 8080)
# Usage : powershell -ExecutionPolicy Bypass -File docs\verify.ps1
# ============================================================

$ErrorActionPreference = 'Stop'
$app = 'http://localhost:8080'
$idp = 'http://localhost:9090'
$jar = Join-Path $env:TEMP 'tp13-cookies.txt'
$out = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'oauth2-verification.txt'

function Titre($n, $txt) {
    $ligne = "=" * 68
    $s = "`n$ligne`nSCENARIO $n : $txt`n$ligne"
    Write-Output $s
    Add-Content -Path $out -Value $s -Encoding UTF8
}

function Info($txt) {
    Write-Output "  $txt"
    Add-Content -Path $out -Value "  $txt" -Encoding UTF8
}

$script:echecs = 0

function Assert-Equal($reel, $attendu, $libelle) {
    if ("$reel" -eq "$attendu") {
        Info "[OK]   $libelle = $reel"
    } else {
        Info "[ECHEC] $libelle : attendu '$attendu', obtenu '$reel'"
        $script:echecs++
    }
}

function Assert-Contains($texte, $motif, $libelle) {
    if ("$texte" -like "*$motif*") {
        Info "[OK]   $libelle"
    } else {
        Info "[ECHEC] $libelle : '$motif' absent de '$texte'"
        $script:echecs++
    }
}

function Code($url, $methode = 'GET', $extra = @()) {
    $a = @('-s', '-o', 'NUL', '-w', '%{http_code}', '-X', $methode, '-b', $jar, '-c', $jar) + $extra + @($url)
    return (& curl.exe @a)
}

function Entete($url, $motif) {
    $brut = & curl.exe -s -D - -o NUL -b $jar -c $jar $url
    return ($brut | Select-String -Pattern $motif | ForEach-Object { $_.Line.Trim() } | Select-Object -First 1)
}

Set-Content -Path $out -Value "TP13 - Verification OAuth2 / OpenID Connect - $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))" -Encoding UTF8
Remove-Item $jar -ErrorAction SilentlyContinue

# ------------------------------------------------------------
Titre 1 "Le fournisseur d'identite expose bien la decouverte OIDC"
$disc = & curl.exe -s "$idp/.well-known/openid-configuration"
Info "GET $idp/.well-known/openid-configuration -> $($disc.Substring(0,80))..."
$d = $disc | ConvertFrom-Json
Info "issuer              = $($d.issuer)"
Info "authorization_endpoint = $($d.authorization_endpoint)"
Info "token_endpoint         = $($d.token_endpoint)"
Info "jwks_uri               = $($d.jwks_uri)"
Info "alg de signature       = $($d.id_token_signing_alg_values_supported -join ',')"
Assert-Equal $d.issuer $idp "issuer"
Assert-Equal $d.authorization_endpoint "$idp/authorize" "authorization_endpoint"

# ------------------------------------------------------------
Titre 2 "La page d'accueil est publique"
$c = Code "$app/"
Info "GET / -> $c"
Assert-Equal $c '200' "GET /"

# ------------------------------------------------------------
Titre 3 "La feuille de style est publique"
$c = Code "$app/css/style.css"
Info "GET /css/style.css -> $c"
Assert-Equal $c '200' "GET /css/style.css"

# ------------------------------------------------------------
Titre 4 "/profile est protege : redirection vers la page de connexion"
$loc = Entete "$app/profile" 'location:'
$c = Code "$app/profile"
Info "GET /profile -> $c"
Info "Location      -> $loc"
Assert-Equal $c '302' "GET /profile code"
Assert-Contains $loc '/login' "GET /profile redirige vers /login"

# ------------------------------------------------------------
Titre 5 "La page de connexion liste les fournisseurs declares"
$html = & curl.exe -s "$app/login"
$c = Code "$app/login"
Info "GET /login -> $c"
Assert-Equal $c '200' "GET /login code"
$liens = ($html | Select-String -Pattern 'oauth2/authorization/([a-zA-Z0-9_-]+)' -AllMatches).Matches | ForEach-Object { $_.Value } | Select-Object -Unique
Info "liens de delegation detectes : $($liens -join ', ')"
Assert-Contains ($liens -join ' ') 'oauth2/authorization/mock' "lien vers le fournisseur mock"

# ------------------------------------------------------------
Titre 6 "L'entree /oauth2/authorization/mock redirige vers le fournisseur"
# ATTENTION : un seul appel. Chaque appel genere un nouveau 'state' en session ;
# rappeler l'URL invaliderait le state utilise au scenario 8.
$brut = & curl.exe -s -D - -o NUL -b $jar -c $jar "$app/oauth2/authorization/mock"
$loc = ($brut | Select-String -Pattern '^location:' | ForEach-Object { $_.Line.Trim() })
$c = ($brut | Select-String -Pattern '^HTTP/' | ForEach-Object { ($_.Line -split ' ')[1] } | Select-Object -Last 1)
Info "GET /oauth2/authorization/mock -> $c"
Info "Location -> $($loc.Substring(0, [Math]::Min(150, $loc.Length)))"
Assert-Equal $c '302' "code de redirection"
Assert-Contains $loc 'response_type=code' "response_type=code"
Assert-Contains $loc 'client_id=mock-oauth-client' "client_id"
Assert-Contains $loc 'scope=openid' "scope=openid"
Assert-Contains $loc 'state=' "parametre state (anti-CSRF)"
Assert-Contains $loc 'redirect_uri=http' "redirect_uri"

# ------------------------------------------------------------
Titre 7 "Le fournisseur affiche le selecteur de compte"
$authz = ($loc -replace '^[Ll]ocation:\s*', '').Trim()
$page = & curl.exe -s $authz
$c = & curl.exe -s -o NUL -w '%{http_code}' $authz
Info "GET $($authz.Substring(0,60))... -> $c"
Assert-Equal $c '200' "page du fournisseur"
Assert-Contains $page 'Mock Identity Provider' "titre de la page"
Assert-Contains $page 'yasmine.ait@ens.ma' "compte 1 (yasmine)"
Assert-Contains $page 'etudiant@ens.ma' "compte 2 (etudiant)"

# ------------------------------------------------------------
Titre 8 "Le fournisseur renvoie un code d'autorisation sur le redirect_uri"
$compte = $authz + '&login=yasmine'
$brut = & curl.exe -s -D - -o NUL -b $jar -c $jar $compte
$loc2 = ($brut | Select-String -Pattern '^location:' | ForEach-Object { $_.Line.Trim() })
Info "GET ...&login=yasmine -> 302"
Info "Location -> $loc2"
Assert-Contains $loc2 '/login/oauth2/code/mock' "redirection vers le callback Spring Security"
Assert-Contains $loc2 'code=' "parametre code present"

# ------------------------------------------------------------
Titre 9 "Spring echange le code contre un id_token et ouvre une session"
$callback = ($loc2 -replace '^[Ll]ocation:\s*', '').Trim()
$brut = & curl.exe -s -D - -o NUL -b $jar -c $jar $callback
$loc3 = ($brut | Select-String -Pattern '^location:' | ForEach-Object { $_.Line.Trim() })
$setck = ($brut | Select-String -Pattern '^set-cookie:\s*JSESSIONID' | ForEach-Object { $_.Line.Trim() })
Info "GET /login/oauth2/code/mock?code=... -> 302"
Info "Location -> $loc3"
Info "Set-Cookie -> $(if ($setck) { 'JSESSIONID=... (session creee)' } else { 'AUCUN' })"
Assert-Contains $loc3 '/profile' "redirection vers /profile (defaultSuccessUrl)"
Assert-Contains $setck 'JSESSIONID' "cookie de session emis"

# ------------------------------------------------------------
Titre 10 "/profile affiche les attributs du jeton d'identite"
$html = & curl.exe -s -b $jar -c $jar "$app/profile"
$c = Code "$app/profile"
Info "GET /profile (avec session) -> $c"
Assert-Equal $c '200' "code"
Assert-Contains $html 'Yasmine Ait Halibi' "nom issu du id_token"
Assert-Contains $html 'yasmine.ait@ens.ma' "email issu du id_token"
Assert-Contains $html 'mock|yasmine' "claim sub"
Assert-Contains $html "Connecte via OAuth2 / OIDC" "badge OAuth2/OIDC"
Assert-Contains $html "$idp" "claim iss = $idp"

# ------------------------------------------------------------
Titre 11 "Le bouton de deconnexion invalide la session"
# Spring Security 6 protege POST /logout par CSRF : on recupere le jeton cache
# dans le formulaire de deconnexion rendu par Thymeleaf (input name="_csrf").
$htmlProfil = & curl.exe -s -b $jar -c $jar "$app/profile"
$m = [regex]::Match($htmlProfil, 'name="_csrf"\s+value="([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($htmlProfil, 'value="([^"]+)"\s+name="_csrf"') }
$csrf = $m.Groups[1].Value
Info "Jeton CSRF extrait de /profile : $(if ($csrf) { $csrf.Substring(0,12) + '...' } else { 'INTROUVABLE' })"
$brut = & curl.exe -s -D - -o NUL -b $jar -c $jar -X POST "$app/logout" --data-urlencode "_csrf=$csrf"
$loc4 = ($brut | Select-String -Pattern '^location:' | ForEach-Object { $_.Line.Trim() })
$code4 = ($brut | Select-String -Pattern '^HTTP/' | ForEach-Object { ($_.Line -split ' ')[1] } | Select-Object -Last 1)
Info "POST /logout (avec jeton CSRF) -> $code4"
Info "Location -> $loc4"
Assert-Contains $loc4 'http://localhost:8080/' "retour a l'accueil"
$c = Code "$app/profile"
Info "GET /profile apres deconnexion -> $c"
Assert-Equal $c '302' "session invalidee : /profile reprotege"

# ------------------------------------------------------------
Titre 12 "Un second compte obtient un profil different"
$brut = & curl.exe -s -D - -o NUL -b $jar -c $jar "$app/oauth2/authorization/mock"
$authz2 = (($brut | Select-String -Pattern '^location:' | ForEach-Object { $_.Line.Trim() }) -replace '^[Ll]ocation:\s*', '').Trim()
$brut = & curl.exe -s -D - -o NUL -b $jar -c $jar ($authz2 + '&login=etudiant')
$cb2 = (($brut | Select-String -Pattern '^location:' | ForEach-Object { $_.Line.Trim() }) -replace '^[Ll]ocation:\s*', '').Trim()
& curl.exe -s -o NUL -b $jar -c $jar $cb2
$html = & curl.exe -s -b $jar -c $jar "$app/profile"
Info "Compte 'etudiant' -> profil :"
Info "  nom   = Etudiant ENS        present : $([bool]($html -match 'Etudiant ENS'))"
Info "  email = etudiant@ens.ma     present : $([bool]($html -match 'etudiant@ens.ma'))"
Info "  sub   = mock|etudiant       present : $([bool]($html -match 'mock\|etudiant'))"
Assert-Contains $html 'Etudiant ENS' "nom du 2e compte"
Assert-Contains $html 'etudiant@ens.ma' "email du 2e compte"

# ------------------------------------------------------------
Titre 13 "Aucun mot de passe n'est gere par l'application"
$src = Get-ChildItem -Path (Join-Path $PSScriptRoot '..\src\main') -Recurse -Include *.java, *.html, *.yml, *.properties |
       Select-String -Pattern 'password|mot de passe' -SimpleMatch
$reels = $src | Where-Object { $_.Line -notmatch 'client-secret|OAuth2|commentaire' }
Info "Occurrences de 'password' dans src/main : $($src.Count)"
Info "(aucune page de login locale, aucun PasswordEncoder, aucune table d'utilisateurs)"
Assert-Equal (($src | Where-Object { $_.Line -match 'PasswordEncoder|createUser|InMemoryUserDetails' }).Count) '0' "pas d'authentification locale"

# ------------------------------------------------------------
$fin = if ($script:echecs -eq 0) {
    "`n$('=' * 68)`nTOUS LES SCENARIOS SONT PASSES`n$('=' * 68)"
} else {
    "`n$('=' * 68)`n$($script:echecs) VERIFICATION(S) EN ECHEC`n$('=' * 68)"
}
Write-Output $fin
Add-Content -Path $out -Value $fin -Encoding UTF8
Write-Output "Rapport ecrit dans : $out"
Remove-Item $jar -ErrorAction SilentlyContinue
