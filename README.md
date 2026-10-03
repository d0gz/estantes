# Estantes

App iOS para catalogar livros jurídicos em estantes virtuais. Projeto de aprendizado.

## Rodar no Mac (macOS Monterey + Xcode 14.2)

```bash
cd ios
xcodegen generate        # gera Estantes.xcodeproj a partir de project.yml
open Estantes.xcodeproj  # rode no simulador de iPhone (iOS 16)
```

Sempre que o `git pull` trouxer arquivos novos, rode `xcodegen generate` de novo.

## Instalar no iPhone

1. GitHub → Actions → **iOS** → **Run workflow**.
2. Ao terminar, baixe o artefato **Estantes-ipa** e descompacte o `.zip` para obter `Estantes.ipa`.
3. Abra o Sideloadly, conecte o iPhone, arraste o `.ipa`, entre com o seu Apple ID e clique em Start.
4. No iPhone: Ajustes → Geral → VPN e Gerenciamento de Dispositivos → confiar no seu Apple ID.
   Na primeira vez, ative também Ajustes → Privacidade e Segurança → Modo de Desenvolvedor.
5. O app vale 7 dias; depois, repita os passos 3 e 4.
