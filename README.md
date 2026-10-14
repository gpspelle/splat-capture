# Splat Capture

*[Português abaixo](#português)*

An iPhone app that films an object for [Splat Studio](https://github.com/gpspelle/splat-studio)
and records where the phone was for every frame, using ARKit. Splat Studio can then skip COLMAP,
its slowest step before training, because the camera positions are already known.

This is the **Phase 0 prototype**: record, save, send to the Mac. It exists to answer one
question: do ARKit's camera positions train a splat as well as COLMAP's? Live coverage and other
recording help come next, once that answer is yes.

## What it does

- Shows the camera with the points ARKit is tracking (yellow dots) and whether tracking is good.
- Records the camera image (HEVC, about 1920 × 1440 at 30 frames a second) and, for every frame,
  the camera position, direction and lens numbers.
- Saves the 3D points ARKit tracked, with their colours, as a starting point cloud.
- Packs each recording into one zip you send to your Mac with AirDrop. The format is described in
  [docs/capture-format.md](docs/capture-format.md).

## Try it on your iPhone

You need a Mac with Xcode, an iPhone with iOS 16 or newer, and a cable. A free Apple account is
enough; you don't need a paid developer account.

1. **Install the tools** (once):
   - Xcode from the Mac App Store. Open it once so it finishes installing.
   - XcodeGen, which makes the Xcode project: `brew install xcodegen`
2. **Get the code and make the project:**
   ```
   git clone https://github.com/gpspelle/splat-capture.git
   cd splat-capture
   xcodegen
   open SplatCapture.xcodeproj
   ```
3. **Sign it with your Apple account** (once): in Xcode choose *Settings › Accounts* and add your
   Apple ID. Then click the **SplatCapture** project, the **SplatCapture** target, *Signing &
   Capabilities*, and pick your name under *Team*. If Xcode says the bundle identifier is taken,
   change it to anything unique, such as `com.yourname.splatcapture`.
4. **Prepare the iPhone** (once): plug it in and tap *Trust*. On iOS 16 or newer, turn on
   *Settings › Privacy & Security › Developer Mode* and let the phone restart.
5. **Run:** pick your iPhone at the top of the Xcode window and press ▶ (Cmd-R). The first time,
   the phone refuses to open an app from an unknown developer: go to *Settings › General › VPN &
   Device Management*, tap your Apple ID and *Trust*, then open Splat Capture.

With a free account the app stops opening after 7 days; press ▶ again to reinstall it. After
`git pull`, run `xcodegen` again before building.

## Recording and sending a capture

1. Open Splat Capture and wait for **Tracking well** (green). Move the phone a little if it says
   *Starting*.
2. Press the red button and walk slowly around the object, keeping it in view: once low, once at
   chest height and once from above, in one take. The *unsteady* number counts frames where
   tracking struggled; keep it low by moving slowly.
3. Press the button again. The capture is saved and the list of captures opens.
4. Tap **Send** and choose your Mac under AirDrop. It lands in *Downloads* as
   `capture_<date>.zip`.

The captures are also in the Files app (*On My iPhone › Splat Capture*) and in Finder when the
phone is plugged in. Swipe left on one to delete it.

## On the Mac: the trial

In Splat Studio (see its README):

```
splat-studio run ~/Downloads/capture_2026-10-14_153012.zip            # train from ARKit's positions
splat-studio trial ~/Downloads/capture_2026-10-14_153012.zip          # compare with COLMAP
```

`trial` makes camera positions three ways from the same frames (ARKit only; ARKit plus COLMAP's
points; COLMAP only), trains each one with the same settings, and reports how long each took and
how good each splat is on frames held out of training.

## Development

```
swift test --package-path CaptureKit      # the format and point cloud code, on the Mac
xcodegen && open SplatCapture.xcodeproj   # the app
```

- `SplatCapture/`: the app (SwiftUI, ARKit, AVFoundation).
- `CaptureKit/`: what doesn't need a camera: the file format, the point cloud, colour conversion.
- `docs/capture-format.md`: the package Splat Studio reads. Change it and Splat Studio together.

GitHub Actions runs the CaptureKit tests and builds the app on every push.

---

## Português

Um app de iPhone que filma um objeto para o [Splat Studio](https://github.com/gpspelle/splat-studio)
e registra onde o celular estava em cada quadro, usando o ARKit. Assim o Splat Studio pode pular o
COLMAP, a etapa mais lenta antes do treino, porque as posições da câmera já são conhecidas.

Este é o **protótipo da Fase 0**: gravar, salvar, enviar para o Mac. Ele existe para responder uma
pergunta: as posições de câmera do ARKit treinam um splat tão bem quanto as do COLMAP? A cobertura
ao vivo e outras ajudas na gravação vêm depois, se a resposta for sim.

### O que ele faz

- Mostra a câmera com os pontos que o ARKit está acompanhando (pontos amarelos) e se o
  rastreamento está bom.
- Grava a imagem da câmera (HEVC, cerca de 1920 × 1440 a 30 quadros por segundo) e, para cada
  quadro, a posição, a direção e os dados da lente.
- Salva os pontos 3D que o ARKit acompanhou, com as cores, como nuvem de pontos inicial.
- Junta cada gravação em um zip que você envia para o Mac por AirDrop. O formato está descrito em
  [docs/capture-format.md](docs/capture-format.md) (em inglês).

### Testar no seu iPhone

Você precisa de um Mac com Xcode, um iPhone com iOS 16 ou mais novo e um cabo. Uma conta Apple
gratuita basta; não precisa de conta de desenvolvedor paga.

1. **Instale as ferramentas** (uma vez):
   - Xcode pela Mac App Store. Abra uma vez para terminar a instalação.
   - XcodeGen, que cria o projeto do Xcode: `brew install xcodegen`
2. **Baixe o código e crie o projeto:**
   ```
   git clone https://github.com/gpspelle/splat-capture.git
   cd splat-capture
   xcodegen
   open SplatCapture.xcodeproj
   ```
3. **Assine com sua conta Apple** (uma vez): no Xcode, escolha *Settings › Accounts* e adicione
   seu Apple ID. Depois clique no projeto **SplatCapture**, no target **SplatCapture**, em
   *Signing & Capabilities*, e escolha seu nome em *Team*. Se o Xcode disser que o bundle
   identifier já existe, troque por algo único, como `com.seunome.splatcapture`.
4. **Prepare o iPhone** (uma vez): conecte e toque em *Confiar*. No iOS 16 ou mais novo, ative
   *Ajustes › Privacidade e Segurança › Modo de Desenvolvedor* e deixe o celular reiniciar.
5. **Rode:** escolha seu iPhone no topo da janela do Xcode e aperte ▶ (Cmd-R). Na primeira vez,
   o celular se recusa a abrir um app de desenvolvedor desconhecido: vá em *Ajustes › Geral › VPN
   e Gerenciamento de Dispositivo*, toque no seu Apple ID e em *Confiar*, e abra o Splat Capture.

Com uma conta gratuita o app para de abrir depois de 7 dias; aperte ▶ de novo para reinstalar.
Depois de `git pull`, rode `xcodegen` de novo antes de compilar.

### Gravar e enviar uma captura

1. Abra o Splat Capture e espere aparecer **Tracking well** (verde). Mexa um pouco o celular se
   aparecer *Starting*.
2. Aperte o botão vermelho e ande devagar ao redor do objeto, sem perdê-lo de vista: uma volta
   baixa, uma na altura do peito e uma de cima, numa gravação só. O número *unsteady* conta os
   quadros em que o rastreamento teve dificuldade; mantenha-o baixo andando devagar.
3. Aperte o botão de novo. A captura é salva e a lista de capturas abre.
4. Toque em **Send** e escolha seu Mac no AirDrop. Ela chega em *Downloads* como
   `capture_<data>.zip`.

As capturas também ficam no app Arquivos (*No Meu iPhone › Splat Capture*) e no Finder quando o
celular está conectado. Deslize para a esquerda para apagar uma.

### No Mac: o teste

No Splat Studio (veja o README dele):

```
splat-studio run ~/Downloads/capture_2026-10-14_153012.zip            # treina com as posições do ARKit
splat-studio trial ~/Downloads/capture_2026-10-14_153012.zip          # compara com o COLMAP
```

O `trial` calcula as posições da câmera de três jeitos a partir dos mesmos quadros (só ARKit;
ARKit mais os pontos do COLMAP; só COLMAP), treina cada um com as mesmas configurações e mostra
quanto tempo cada um levou e a qualidade de cada splat em quadros deixados de fora do treino.

### Desenvolvimento

```
swift test --package-path CaptureKit      # o código do formato e da nuvem de pontos, no Mac
xcodegen && open SplatCapture.xcodeproj   # o app
```

- `SplatCapture/`: o app (SwiftUI, ARKit, AVFoundation).
- `CaptureKit/`: o que não precisa de câmera: o formato dos arquivos, a nuvem de pontos, a
  conversão de cores.
- `docs/capture-format.md`: o pacote que o Splat Studio lê. Mude-o junto com o Splat Studio.

O GitHub Actions roda os testes do CaptureKit e compila o app a cada push.
