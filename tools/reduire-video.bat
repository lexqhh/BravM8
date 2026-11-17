@echo off
setlocal
rem Reduit des videos pour pouvoir les envoyer dans medias/ sur GitHub (limite 25 Mo par fichier).
rem Utilisation : glisser une ou plusieurs videos (ou GIF) sur ce fichier.
rem Les copies reduites vont dans un dossier "pour-BravM8" a cote des originales, qui ne sont pas modifiees.
rem En jeu, les clips sont affiches en 200 px a 10 images/s : passer en 480p ne fait rien perdre.

where ffmpeg >nul 2>&1
if errorlevel 1 (
    echo ffmpeg est introuvable. Installe-le avec cette commande, puis relance :
    echo     winget install Gyan.FFmpeg
    pause
    exit /b 1
)

if "%~1"=="" (
    echo Glisse une ou plusieurs videos sur ce fichier pour les reduire.
    pause
    exit /b 0
)

:suivante
if "%~1"=="" goto fin
set "sortie=%~dp1pour-BravM8"
if not exist "%sortie%" mkdir "%sortie%"
echo.
echo Reduction de %~nx1 ...
ffmpeg -y -v error -stats -i "%~1" -t 60 -vf "scale=-2:'min(480,trunc(ih/2)*2)'" -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "%sortie%\%~n1.mp4"
if errorlevel 1 (
    echo   Echec pour %~nx1
) else (
    for %%F in ("%sortie%\%~n1.mp4") do echo   OK : %%~zF octets
)
shift
goto suivante

:fin
echo.
echo Termine. Les videos reduites sont dans le dossier pour-BravM8, a cote des originales.
echo Envoie-les ensuite dans le dossier medias/ du depot GitHub.
pause
