BINARY     := gnp-agent
BUILD_DIR  := build
MODULE     := gnp-agent

.PHONY: all build test test-unit test-integration lint clean run help

all: build

## build: Compila el binario en ./build/gnp-agent
build:
	@mkdir -p $(BUILD_DIR)
	go build -o $(BUILD_DIR)/$(BINARY) ./cmd/gnp-agent/
	@echo "✓ Build: $(BUILD_DIR)/$(BINARY)"

## test-unit: Corre solo tests unitarios (sin API key)
test-unit:
	go test ./internal/state/... ./internal/parser/... -run "TestValidate|TestMember|TestSchema|TestManager|TestSessionProgress|TestMark" -v

## test-integration: Corre todos los tests incluyendo llamadas a Claude API
test-integration:
	@if [ -z "$$ANTHROPIC_API_KEY" ]; then \
		echo "ERROR: ANTHROPIC_API_KEY no definida"; exit 1; fi
	go test ./... -v -timeout 120s

## test: Corre tests unitarios (default, no requiere API key)
test: test-unit

## run-stdin: Ejecuta el agente leyendo ticket desde stdin
run-stdin: build
	$(BUILD_DIR)/$(BINARY)

## run-dry: Ejecuta en modo dry-run con un archivo de ticket
## Uso: make run-dry TICKET=mi_ticket.txt
run-dry: build
	$(BUILD_DIR)/$(BINARY) -ticket $(TICKET) -dry-run

## status: Muestra el estado de los tickets de la sesión
status: build
	$(BUILD_DIR)/$(BINARY) -status

## example: Corre con el ejemplo de CTASK0359698 (Secret Manager IAM)
example: build
	@echo "Siguiente tarea\nCTASK0359698\n\nArtefacto: Permisos a secretos\nTipoTarea: Manual\nOwner: InfraTeam\nTECNOLOGÍA: Google Cloud\nProyecto: gnp-wsbancasegurogmm-qa\n\nIndicaciones:\nAgregar permisos para ver los secretos gae-ws-bancaseguro@gnp-wsbancasegurogmm-qa.iam.gserviceaccount.com\n\nSecret Manager\nName.- key_banca\nName.- secret_banca" \
		| $(BUILD_DIR)/$(BINARY)

## lint: Corre go vet
lint:
	go vet ./...

## clean: Elimina el directorio build
clean:
	rm -rf $(BUILD_DIR)

## help: Muestra esta ayuda
help:
	@grep -E '^## ' Makefile | sed 's/## //'
