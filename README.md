# Wave Music — Flutter para Android

Aplicativo independente de música, com interface escura e detalhes azuis.

## Estado desta versão (0.2.0)

Implementado:
- Interface Flutter com Início, Buscar e Biblioteca.
- Seleção de vários arquivos de áudio do dispositivo.
- Reprodução local com `just_audio`.
- Mini-player com play/pause e próxima faixa.
- Serviço de áudio em segundo plano e notificação de mídia via `just_audio_background`.
- Workflow do GitHub Actions para compilar APK release.

Ainda não implementado:
- Streaming/catálogo online.
- Letras sincronizadas.
- Importação de playlists de Spotify, Apple Music ou Deezer.
- Playlists editáveis, favoritos persistentes e histórico.
- Busca online, login e sincronização entre dispositivos.

Esses recursos dependem de APIs, permissões e serviços oficiais. Este projeto não reutiliza código, marca ou design proprietário do Liner.

## Compilar pelo GitHub

O workflow `.github/workflows/android-apk.yml` executa quando há push na branch `main`/`master` ou manualmente pela aba Actions.

1. Envie os arquivos deste projeto para a raiz do repositório.
2. Abra **Actions** e selecione **Build Wave Music APK**.
3. Aguarde a execução terminar.
4. Em Artifacts, baixe `wave-music-android-apk`.
5. Extraia o ZIP do artifact e instale `app-release.apk` no Android.

Não é necessário instalar Flutter ou Android SDK no Termux. O workflow gera a estrutura Android e compila na máquina do GitHub Actions.

## Termux: enviar a versão

Veja as instruções de envio no arquivo `COMANDO-TERMUX.txt`. Ajuste a pasta local caso tenha escolhido outro nome.

## Observação

O APK é uma build release de teste, não uma publicação assinada para Play Store. Para publicar, será necessário configurar uma chave de assinatura e os requisitos atuais da loja.
