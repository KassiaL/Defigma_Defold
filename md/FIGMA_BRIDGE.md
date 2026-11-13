# Figma

Figma is reached only through Figma Bridge (`~/figma_plugins/FigmaBridge`, protocol in its `README.md`).

## Ports

| what | value |
|---|---|
| Figma Bridge port | `8795` (`~/figma_plugins/FigmaBridge/start.sh 8795`) |

The plugin reads the bridge port from the file's Defigma settings node (`{"defigma":{...,"bridge_port":8795}}`)
when it starts, so run the plugin in this project's file and its jobs go to `8795`.
Jobs: `python3 ~/figma_plugins/FigmaBridge/figma.py --port 8795 health`.
