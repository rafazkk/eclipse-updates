# Atualizações do Eclipse

Esta área pública contém somente os arquivos distribuídos aos jogadores.
O projeto original e o código-fonte C++ continuam no repositório privado.

Os arquivos em `site/` são preparados pelo repositório principal. O pacote
inicial já está disponível no GitHub Pages:
`https://rafazkk.github.io/eclipse-updates/manifest.json`.
Não faça alterações manuais em `site/`: a publicação seguinte substitui seu conteúdo.

A publicação automática de novas versões depende de aprovar o workflow no
repositório privado e configurar ali o segredo `ECLIPSE_UPDATES_TOKEN`, restrito
somente a este repositório público com permissão `Contents: Read and write`.
O launcher não usa esse segredo: os downloads são públicos por HTTPS.
