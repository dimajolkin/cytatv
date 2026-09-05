module cytatv

go 1.22.0

require (
	github.com/dimajolkin/eMMC153-Writer v0.0.0
	github.com/spf13/cobra v1.9.1
	github.com/yaml/go-yaml-dom v0.1.2
	go.bug.st/serial v1.6.2
	go.yaml.in/yaml/v4 v4.0.0-rc.6
	gopkg.in/yaml.v3 v3.0.1
)

require (
	github.com/creack/goselect v0.1.2 // indirect
	github.com/inconshreveable/mousetrap v1.1.0 // indirect
	github.com/spf13/pflag v1.0.6 // indirect
	golang.org/x/sys v0.30.0 // indirect
)

replace github.com/dimajolkin/eMMC153-Writer => ../eMMC153-Writer
