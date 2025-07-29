# Discourse BBB Plugin Makefile

# Variables
DISCOURSE_VERSION = 3.5.0.beta8-dev
COMMIT_HASH = $(shell git rev-parse HEAD)

# Comandos principales
.PHONY: update-compatibility rebuild help

# Actualizar compatibilidad y hacer commit/push
update-compatibility:
	@echo "Actualizando .discourse-compatibility con commit $(COMMIT_HASH)..."
	@echo "$(DISCOURSE_VERSION): $(COMMIT_HASH)" > .discourse-compatibility
	@git add .
	@git commit -m "update compatibility"
	@git push
	@echo "✅ Compatibilidad actualizada y pusheada"

# Comando completo: actualizar compatibilidad + rebuild
rebuild: update-compatibility
	@echo "🔄 Iniciando rebuild de Discourse..."
	@echo "Ahora puedes ejecutar el rebuild de Docker"

# Mostrar ayuda
help:
	@echo "Comandos disponibles:"
	@echo "  make update-compatibility  - Actualiza .discourse-compatibility y hace push"
	@echo "  make rebuild              - Ejecuta update-compatibility + mensaje para rebuild"
	@echo "  make help                 - Muestra esta ayuda"
	@echo ""
	@echo "Variables:"
	@echo "  DISCOURSE_VERSION: $(DISCOURSE_VERSION)"
	@echo "  COMMIT_HASH: $(COMMIT_HASH)"

# Target por defecto
.DEFAULT_GOAL := help
