module kpango.com/dotfiles/mod

go 1.25.3

tool (
	github.com/99designs/gqlgen
	github.com/a8m/syncmap
	github.com/amacneil/dbmate
	github.com/bojand/ghz/cmd/ghz
	github.com/bonnefoa/kubectl-fzf/v3/cmd/kubectl-fzf-completion
	github.com/bonnefoa/kubectl-fzf/v3/cmd/kubectl-fzf-server
	github.com/bufbuild/buf/cmd/buf
	github.com/bufbuild/connect-go/cmd/protoc-gen-connect-go
	github.com/cockroachdb/crlfmt
	github.com/cweill/gotests/gotests
	github.com/davidrjenni/reftools/cmd/fillstruct
	github.com/davidrjenni/reftools/cmd/fillswitch
	github.com/davidrjenni/reftools/cmd/fixplurals
	github.com/direnv/direnv
	github.com/fatih/gomodifytags
	github.com/fullstorydev/grpcurl
	github.com/fullstorydev/grpcurl/cmd/grpcurl
	github.com/github/hub
	github.com/gnewton/chidley
	github.com/go-delve/delve/cmd/dlv
	github.com/go-kratos/kratos/cmd/kratos
	github.com/go-task/task/v3/cmd/task
	github.com/golang/mock/mockgen
	github.com/google/yamlfmt/cmd/yamlfmt
	github.com/gotesttools/gotestfmt/v2/cmd/gotestfmt
	github.com/helmfile/helmfile
	github.com/hexdigest/gowrap/cmd/gowrap
	github.com/hidetatz/kubecolor/cmd/kubecolor
	github.com/incu6us/goimports-reviser
	github.com/instrumenta/kubeval
	github.com/isaacphi/mcp-language-server
	github.com/josharian/impl
	github.com/jstemmer/gotags
	github.com/kisielk/errcheck
	github.com/koron/iferr
	github.com/ktr0731/evans
	github.com/mattiamari/reddit2wallpaper/cmd/reddit2wallpaper
	github.com/mattn/efm-langserver
	github.com/mfridman/tparse
	github.com/mkimuram/k8sviz/cmd/k8sviz
	github.com/momotaro98/strictgoimports/cmd/strictgoimports
	github.com/muesli/duf
	github.com/nsf/gocode
	github.com/orisano/dlayer
	github.com/pwaller/goimports-update-ignore
	github.com/quasilyte/go-ruleguard/cmd/ruleguard
	github.com/rerost/dragon-imports
	github.com/rerost/dragon-imports/cmd/dragon-imports
	github.com/rs/xid
	github.com/securego/gosec/v2/cmd/gosec
	github.com/siderolabs/talos/cmd/talosctl
	github.com/sqs/goreturns
	github.com/tendermint/tendermint/libs/pubsub
	github.com/tsenart/vegeta
	github.com/uber/prototool/cmd/prototool
	github.com/vugu/vgrun
	github.com/x-motemen/ghq
	github.com/y4v8/gojson/gojson
	github.com/yannh/kubeconform/cmd/kubeconform
	golang.org/dl/gotip
	golang.org/x/lint/golint
	golang.org/x/review/git-codereview
	golang.org/x/tools/cmd/go-contrib-init
	golang.org/x/tools/cmd/godoc
	golang.org/x/tools/cmd/goimports
	golang.org/x/tools/go/analysis/passes/fieldalignment
	golang.org/x/vuln/cmd/govulncheck
	google.golang.org/protobuf/cmd/protoc-gen-go
	mvdan.cc/gofumpt
	mvdan.cc/sh/v3/cmd/shfmt
	sigs.k8s.io/kind/cmd/kind
	sigs.k8s.io/kubectl-check-ownerreferences
	sigs.k8s.io/kustomize/kustomize/v5
)

replace github.com/ugorji/go => github.com/ugorji/go v1.2.14

require (
	al.essio.dev/pkg/shellescape v1.6.0 // indirect
	buf.build/gen/go/bufbuild/bufplugin/protocolbuffers/go v1.36.10-20250718181942-e35f9b667443.1 // indirect
	buf.build/gen/go/bufbuild/protovalidate/protocolbuffers/go v1.36.10-20250912141014-52f32327d4b0.1 // indirect
	buf.build/gen/go/bufbuild/registry/connectrpc/go v1.19.1-20250924144421-cb55f06efbd2.2 // indirect
	buf.build/gen/go/bufbuild/registry/protocolbuffers/go v1.36.10-20250924144421-cb55f06efbd2.1 // indirect
	buf.build/gen/go/pluginrpc/pluginrpc/protocolbuffers/go v1.36.10-20241007202033-cf42259fcbfc.1 // indirect
	buf.build/go/app v0.1.0 // indirect
	buf.build/go/bufplugin v0.9.0 // indirect
	buf.build/go/interrupt v1.1.0 // indirect
	buf.build/go/protovalidate v1.0.0 // indirect
	buf.build/go/protoyaml v0.6.0 // indirect
	buf.build/go/spdx v0.2.0 // indirect
	buf.build/go/standard v0.1.0 // indirect
	cel.dev/expr v0.24.0 // indirect
	cloud.google.com/go v0.123.0 // indirect
	cloud.google.com/go/auth v0.17.0 // indirect
	cloud.google.com/go/auth/oauth2adapt v0.2.8 // indirect
	cloud.google.com/go/compute/metadata v0.9.0 // indirect
	cloud.google.com/go/iam v1.5.3 // indirect
	cloud.google.com/go/kms v1.23.2 // indirect
	cloud.google.com/go/longrunning v0.7.0 // indirect
	cloud.google.com/go/monitoring v1.24.3 // indirect
	cloud.google.com/go/secretmanager v1.15.1 // indirect
	cloud.google.com/go/storage v1.57.0 // indirect
	connectrpc.com/connect v1.19.1 // indirect
	connectrpc.com/otelconnect v0.8.0 // indirect
	dario.cat/mergo v1.0.2 // indirect
	filippo.io/age v1.2.1 // indirect
	filippo.io/edwards25519 v1.1.0 // indirect
	github.com/1Password/connect-sdk-go v1.5.3 // indirect
	github.com/1password/onepassword-sdk-go v0.3.1 // indirect
	github.com/99designs/gqlgen v0.17.81 // indirect
	github.com/AlecAivazis/survey/v2 v2.3.7 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/azcore v1.19.1 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/azidentity v1.13.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/internal v1.11.2 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/storage/armstorage v1.8.1 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/security/keyvault/azcertificates v1.4.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/security/keyvault/azkeys v1.4.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/security/keyvault/azsecrets v1.4.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/security/keyvault/internal v1.2.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/storage/azblob v1.6.2 // indirect
	github.com/Azure/go-ansiterm v0.0.0-20250102033503-faa5f7b0171c // indirect
	github.com/Azure/go-autorest v14.2.0+incompatible // indirect
	github.com/Azure/go-autorest/autorest/adal v0.9.24 // indirect
	github.com/Azure/go-autorest/autorest/azure/cli v0.4.7 // indirect
	github.com/Azure/go-autorest/autorest/date v0.3.1 // indirect
	github.com/Azure/go-autorest/logger v0.2.2 // indirect
	github.com/Azure/go-autorest/tracing v0.6.1 // indirect
	github.com/AzureAD/microsoft-authentication-library-for-go v1.5.0 // indirect
	github.com/BurntSushi/toml v1.5.0 // indirect
	github.com/ChimeraCoder/gojson v1.1.0 // indirect
	github.com/ClickHouse/clickhouse-go v1.5.4 // indirect
	github.com/DopplerHQ/cli v0.5.11-0.20230908185655-7aef4713e1a4 // indirect
	github.com/GoogleCloudPlatform/opentelemetry-operations-go/detectors/gcp v1.30.0 // indirect
	github.com/GoogleCloudPlatform/opentelemetry-operations-go/exporter/metric v0.54.0 // indirect
	github.com/GoogleCloudPlatform/opentelemetry-operations-go/internal/resourcemapping v0.54.0 // indirect
	github.com/IGLOU-EU/go-wildcard v1.0.3 // indirect
	github.com/Ladicle/tabwriter v1.0.0 // indirect
	github.com/MakeNowJust/heredoc v1.0.0 // indirect
	github.com/Masterminds/goutils v1.1.1 // indirect
	github.com/Masterminds/semver/v3 v3.4.0 // indirect
	github.com/Masterminds/sprig/v3 v3.3.0 // indirect
	github.com/Masterminds/squirrel v1.5.4 // indirect
	github.com/Microsoft/go-winio v0.6.2 // indirect
	github.com/ProtonMail/go-crypto v1.3.0 // indirect
	github.com/ProtonMail/go-mime v0.0.0-20230322103455-7d82a3887f2f // indirect
	github.com/ProtonMail/gopenpgp/v2 v2.9.0 // indirect
	github.com/Songmu/gitconfig v0.2.1 // indirect
	github.com/a8m/envsubst v1.4.3 // indirect
	github.com/a8m/syncmap v0.0.0-20220625115200-192175abec13 // indirect
	github.com/adrg/xdg v0.5.3 // indirect
	github.com/agext/levenshtein v1.2.3 // indirect
	github.com/agnivade/levenshtein v1.2.1 // indirect
	github.com/alecthomas/chroma/v2 v2.20.0 // indirect
	github.com/alecthomas/kingpin v1.3.8-0.20191105203113-8c96d1c22481 // indirect
	github.com/alecthomas/template v0.0.0-20190718012654-fb15b899a751 // indirect
	github.com/alecthomas/units v0.0.0-20240927000941-0f3dac36c52b // indirect
	github.com/alexflint/go-filemutex v1.3.0 // indirect
	github.com/amacneil/dbmate v1.16.2 // indirect
	github.com/antchfx/jsonquery v1.3.6 // indirect
	github.com/antchfx/xpath v1.3.5 // indirect
	github.com/anthropics/anthropic-sdk-go v1.14.0 // indirect
	github.com/antlr4-go/antlr/v4 v4.13.1 // indirect
	github.com/apparentlymart/go-textseg/v15 v15.0.0 // indirect
	github.com/araddon/dateparse v0.0.0-20210429162001-6b43995a97de // indirect
	github.com/armon/circbuf v0.0.0-20190214190532-5111143e8da2 // indirect
	github.com/asaskevich/govalidator v0.0.0-20230301143203-a9d515a09cc2 // indirect
	github.com/atotto/clipboard v0.1.4 // indirect
	github.com/awalterschulze/gographviz v2.0.3+incompatible // indirect
	github.com/aws/aws-sdk-go v1.55.8 // indirect
	github.com/aws/aws-sdk-go-v2 v1.39.2 // indirect
	github.com/aws/aws-sdk-go-v2/aws/protocol/eventstream v1.7.1 // indirect
	github.com/aws/aws-sdk-go-v2/config v1.31.12 // indirect
	github.com/aws/aws-sdk-go-v2/credentials v1.18.16 // indirect
	github.com/aws/aws-sdk-go-v2/feature/ec2/imds v1.18.9 // indirect
	github.com/aws/aws-sdk-go-v2/feature/s3/manager v1.19.12 // indirect
	github.com/aws/aws-sdk-go-v2/internal/configsources v1.4.9 // indirect
	github.com/aws/aws-sdk-go-v2/internal/endpoints/v2 v2.7.9 // indirect
	github.com/aws/aws-sdk-go-v2/internal/ini v1.8.3 // indirect
	github.com/aws/aws-sdk-go-v2/internal/v4a v1.4.9 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/accept-encoding v1.13.1 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/checksum v1.9.0 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/presigned-url v1.13.9 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/s3shared v1.19.9 // indirect
	github.com/aws/aws-sdk-go-v2/service/kms v1.45.6 // indirect
	github.com/aws/aws-sdk-go-v2/service/s3 v1.88.4 // indirect
	github.com/aws/aws-sdk-go-v2/service/secretsmanager v1.39.6 // indirect
	github.com/aws/aws-sdk-go-v2/service/ssm v1.65.1 // indirect
	github.com/aws/aws-sdk-go-v2/service/sso v1.29.6 // indirect
	github.com/aws/aws-sdk-go-v2/service/ssooidc v1.35.1 // indirect
	github.com/aws/aws-sdk-go-v2/service/sts v1.38.6 // indirect
	github.com/aws/smithy-go v1.23.1 // indirect
	github.com/aymanbagabas/go-osc52/v2 v2.0.1 // indirect
	github.com/bahlo/generic-list-go v0.2.0 // indirect
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/bgentry/go-netrc v0.0.0-20140422174119-9fd32a8b3d3d // indirect
	github.com/blang/semver v3.5.1+incompatible // indirect
	github.com/blang/semver/v4 v4.0.0 // indirect
	github.com/bmatcuk/doublestar/v4 v4.9.1 // indirect
	github.com/bmizerany/perks v0.0.0-20230307044200-03f9df79da1e // indirect
	github.com/bojand/ghz v0.120.0 // indirect
	github.com/bonnefoa/kubectl-fzf/v3 v3.0.4 // indirect
	github.com/btcsuite/btcd v0.22.1 // indirect
	github.com/bufbuild/buf v1.58.0 // indirect
	github.com/bufbuild/connect-go v1.10.0 // indirect
	github.com/bufbuild/protocompile v0.14.1 // indirect
	github.com/bufbuild/protoplugin v0.0.0-20250218205857-750e09ce93e1 // indirect
	github.com/buger/jsonparser v1.1.1 // indirect
	github.com/bytedance/gopkg v0.1.3 // indirect
	github.com/bytedance/sonic v1.14.1 // indirect
	github.com/bytedance/sonic/loader v0.3.0 // indirect
	github.com/c2h5oh/datasize v0.0.0-20231215233829-aa82cc1e6500 // indirect
	github.com/ccojocar/zxcvbn-go v1.0.4 // indirect
	github.com/cenkalti/backoff/v4 v4.3.0 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/chai2010/gettext-go v1.0.3 // indirect
	github.com/chainguard-dev/git-urls v1.0.2 // indirect
	github.com/charmbracelet/colorprofile v0.3.2 // indirect
	github.com/charmbracelet/lipgloss v1.1.1-0.20250319133953-166f707985bc // indirect
	github.com/charmbracelet/x/ansi v0.10.2 // indirect
	github.com/charmbracelet/x/cellbuf v0.0.13 // indirect
	github.com/charmbracelet/x/term v0.2.1 // indirect
	github.com/chzyer/readline v1.5.1 // indirect
	github.com/cilium/ebpf v0.19.0 // indirect
	github.com/cli/go-gh/v2 v2.12.2 // indirect
	github.com/cli/safeexec v1.0.1 // indirect
	github.com/clipperhouse/uax29/v2 v2.2.0 // indirect
	github.com/cloudflare/circl v1.6.1 // indirect
	github.com/cloudflare/golz4 v0.0.0-20240916140612-caecf3c00c06 // indirect
	github.com/cloudwego/base64x v0.1.6 // indirect
	github.com/cncf/xds/go v0.0.0-20251014123835-2ee22ca58382 // indirect
	github.com/cockroachdb/crlfmt v0.3.0 // indirect
	github.com/cockroachdb/gostdlib v1.19.0 // indirect
	github.com/containerd/containerd v1.7.28 // indirect
	github.com/containerd/errdefs v1.0.0 // indirect
	github.com/containerd/errdefs/pkg v0.3.0 // indirect
	github.com/containerd/go-cni v1.1.13 // indirect
	github.com/containerd/log v0.1.0 // indirect
	github.com/containerd/platforms v1.0.0-rc.1 // indirect
	github.com/containerd/stargz-snapshotter/estargz v0.17.0 // indirect
	github.com/containernetworking/cni v1.3.0 // indirect
	github.com/containernetworking/plugins v1.8.0 // indirect
	github.com/coreos/go-iptables v0.8.0 // indirect
	github.com/coreos/go-semver v0.3.1 // indirect
	github.com/coreos/go-systemd/v22 v22.6.0 // indirect
	github.com/cosi-project/runtime v1.11.0 // indirect
	github.com/cosiner/argv v0.1.0 // indirect
	github.com/cpuguy83/go-md2man/v2 v2.0.7 // indirect
	github.com/cweill/gotests v1.6.0 // indirect
	github.com/cyberark/conjur-api-go v0.13.7 // indirect
	github.com/cyphar/filepath-securejoin v0.5.0 // indirect
	github.com/danieljoos/wincred v1.2.3 // indirect
	github.com/davecgh/go-spew v1.1.2-0.20180830191138-d8f796af33cc // indirect
	github.com/daviddengcn/go-colortext v1.0.0 // indirect
	github.com/davidrjenni/reftools v0.0.0-20250907133731-34b10582faa4 // indirect
	github.com/derekparker/trie v0.0.0-20230829180723-39f4de51ef7d // indirect
	github.com/detailyang/go-fallocate v0.0.0-20180908115635-432fa640bd2e // indirect
	github.com/dgryski/go-gk v0.0.0-20200319235926-a69029f61654 // indirect
	github.com/dgryski/go-lttb v0.0.0-20230207170358-f8fc36cdbff1 // indirect
	github.com/dimchansky/utfbom v1.1.1 // indirect
	github.com/direnv/direnv v2.20.1+incompatible // indirect
	github.com/direnv/go-dotenv v0.0.0-20240228124046-4d7e6004a1a8 // indirect
	github.com/distribution/reference v0.6.0 // indirect
	github.com/dlclark/regexp2 v1.11.5 // indirect
	github.com/docker/cli v28.5.1+incompatible // indirect
	github.com/docker/distribution v2.8.3+incompatible // indirect
	github.com/docker/docker v28.5.1+incompatible // indirect
	github.com/docker/docker-credential-helpers v0.9.4 // indirect
	github.com/docker/go-connections v0.6.0 // indirect
	github.com/docker/go-units v0.5.0 // indirect
	github.com/dominikbraun/graph v0.23.0 // indirect
	github.com/dustin/go-humanize v1.0.1 // indirect
	github.com/dylibso/observe-sdk/go v0.0.0-20240828172851-9145d8ad07e1 // indirect
	github.com/elliotchance/orderedmap/v3 v3.1.0 // indirect
	github.com/emicklei/dot v1.9.2 // indirect
	github.com/emicklei/go-restful/v3 v3.13.0 // indirect
	github.com/emicklei/proto v1.14.2 // indirect
	github.com/emirpasic/gods v1.18.1 // indirect
	github.com/envoyproxy/go-control-plane/envoy v1.35.0 // indirect
	github.com/envoyproxy/protoc-gen-validate v1.2.1 // indirect
	github.com/evanphx/json-patch v5.9.11+incompatible // indirect
	github.com/evanphx/json-patch/v5 v5.9.11 // indirect
	github.com/exponent-io/jsonpath v0.0.0-20210407135951-1de76d718b3f // indirect
	github.com/extism/go-sdk v1.7.1 // indirect
	github.com/fatih/camelcase v1.0.0 // indirect
	github.com/fatih/color v1.18.0 // indirect
	github.com/fatih/gomodifytags v1.17.0 // indirect
	github.com/fatih/structtag v1.2.0 // indirect
	github.com/felixge/fgprof v0.9.5 // indirect
	github.com/felixge/httpsnoop v1.0.4 // indirect
	github.com/florianl/go-tc v0.4.7 // indirect
	github.com/foxboron/go-uefi v0.0.0-20251010190908-d29549a44f29 // indirect
	github.com/fsnotify/fsnotify v1.9.0 // indirect
	github.com/fujiwara/tfstate-lookup v1.7.1 // indirect
	github.com/fullstorydev/grpcurl v1.9.3 // indirect
	github.com/fxamacker/cbor/v2 v2.9.0 // indirect
	github.com/gabriel-vasile/mimetype v1.4.10 // indirect
	github.com/gdamore/encoding v1.0.1 // indirect
	github.com/gdamore/tcell/v2 v2.9.0 // indirect
	github.com/gertd/go-pluralize v0.2.1 // indirect
	github.com/getsops/gopgagent v0.0.0-20241224165529-7044f28e491e // indirect
	github.com/getsops/sops/v3 v3.11.0 // indirect
	github.com/ghodss/yaml v1.0.0 // indirect
	github.com/gin-contrib/sse v1.1.0 // indirect
	github.com/gin-gonic/gin v1.11.0 // indirect
	github.com/github/hub v2.11.2+incompatible // indirect
	github.com/gizak/termui/v3 v3.1.0 // indirect
	github.com/gnewton/chidley v0.0.0-20211230221022-09b9269092fb // indirect
	github.com/go-chi/chi/v5 v5.2.3 // indirect
	github.com/go-delve/delve v1.25.2 // indirect
	github.com/go-delve/liner v1.2.3-0.20231231155935-4726ab1d7f62 // indirect
	github.com/go-errors/errors v1.5.1 // indirect
	github.com/go-git/gcfg v1.5.1-0.20230307220236-3a3c6141e376 // indirect
	github.com/go-git/go-billy/v5 v5.6.2 // indirect
	github.com/go-git/go-git/v5 v5.16.3 // indirect
	github.com/go-gorp/gorp/v3 v3.1.0 // indirect
	github.com/go-jose/go-jose/v4 v4.1.3 // indirect
	github.com/go-kratos/kratos/cmd/kratos v0.0.0-20210217095515-c4e4aa563867 // indirect
	github.com/go-logr/logr v1.4.3 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/go-openapi/analysis v0.24.0 // indirect
	github.com/go-openapi/errors v0.22.3 // indirect
	github.com/go-openapi/jsonpointer v0.22.1 // indirect
	github.com/go-openapi/jsonreference v0.21.2 // indirect
	github.com/go-openapi/loads v0.23.1 // indirect
	github.com/go-openapi/runtime v0.29.0 // indirect
	github.com/go-openapi/spec v0.22.0 // indirect
	github.com/go-openapi/strfmt v0.24.0 // indirect
	github.com/go-openapi/swag v0.25.1 // indirect
	github.com/go-openapi/swag/cmdutils v0.25.1 // indirect
	github.com/go-openapi/swag/conv v0.25.1 // indirect
	github.com/go-openapi/swag/fileutils v0.25.1 // indirect
	github.com/go-openapi/swag/jsonname v0.25.1 // indirect
	github.com/go-openapi/swag/jsonutils v0.25.1 // indirect
	github.com/go-openapi/swag/loading v0.25.1 // indirect
	github.com/go-openapi/swag/mangling v0.25.1 // indirect
	github.com/go-openapi/swag/netutils v0.25.1 // indirect
	github.com/go-openapi/swag/stringutils v0.25.1 // indirect
	github.com/go-openapi/swag/typeutils v0.25.1 // indirect
	github.com/go-openapi/swag/yamlutils v0.25.1 // indirect
	github.com/go-openapi/validate v0.25.0 // indirect
	github.com/go-playground/locales v0.14.1 // indirect
	github.com/go-playground/universal-translator v0.18.1 // indirect
	github.com/go-playground/validator/v10 v10.28.0 // indirect
	github.com/go-sql-driver/mysql v1.9.3 // indirect
	github.com/go-task/slim-sprig/v3 v3.0.0 // indirect
	github.com/go-task/task/v3 v3.45.4 // indirect
	github.com/go-task/template v0.2.0 // indirect
	github.com/go-toolsmith/astcopy v1.1.0 // indirect
	github.com/go-toolsmith/astequal v1.2.0 // indirect
	github.com/go-viper/mapstructure/v2 v2.4.0 // indirect
	github.com/gobuffalo/flect v1.0.3 // indirect
	github.com/gobwas/glob v0.2.3 // indirect
	github.com/goccy/go-json v0.10.5 // indirect
	github.com/goccy/go-yaml v1.18.0 // indirect
	github.com/godbus/dbus/v5 v5.1.0 // indirect
	github.com/gofrs/flock v0.13.0 // indirect
	github.com/gogo/protobuf v1.3.2 // indirect
	github.com/golang-jwt/jwt/v4 v4.5.2 // indirect
	github.com/golang-jwt/jwt/v5 v5.3.0 // indirect
	github.com/golang/groupcache v0.0.0-20241129210726-2c02b8208cf8 // indirect
	github.com/golang/mock v1.6.0 // indirect
	github.com/golang/protobuf v1.5.4 // indirect
	github.com/google/btree v1.1.3 // indirect
	github.com/google/cel-go v0.26.1 // indirect
	github.com/google/gnostic-models v0.7.0 // indirect
	github.com/google/go-cmp v0.7.0 // indirect
	github.com/google/go-containerregistry v0.20.6 // indirect
	github.com/google/go-dap v0.12.0 // indirect
	github.com/google/go-github v17.0.0+incompatible // indirect
	github.com/google/go-jsonnet v0.21.0 // indirect
	github.com/google/go-querystring v1.1.0 // indirect
	github.com/google/go-tpm v0.9.6 // indirect
	github.com/google/pprof v0.0.0-20251007162407-5df77e3f7d1d // indirect
	github.com/google/renameio/v2 v2.0.0 // indirect
	github.com/google/s2a-go v0.1.9 // indirect
	github.com/google/shlex v0.0.0-20191202100458-e7afc7fbc510 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/google/yamlfmt v0.18.0 // indirect
	github.com/googleapis/enterprise-certificate-proxy v0.3.6 // indirect
	github.com/googleapis/gax-go/v2 v2.15.0 // indirect
	github.com/gookit/color v1.6.0 // indirect
	github.com/gopacket/gopacket v1.4.0 // indirect
	github.com/gorilla/websocket v1.5.4-0.20250319132907-e064f32e3674 // indirect
	github.com/gosuri/uilive v0.0.4 // indirect
	github.com/gosuri/uiprogress v0.0.1 // indirect
	github.com/gosuri/uitable v0.0.4 // indirect
	github.com/gotesttools/gotestfmt/v2 v2.5.0 // indirect
	github.com/goware/prefixer v0.0.0-20160118172347-395022866408 // indirect
	github.com/gregjones/httpcache v0.0.0-20190611155906-901d90724c79 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.27.3 // indirect
	github.com/hashicorp/aws-sdk-go-base/v2 v2.0.0-beta.67 // indirect
	github.com/hashicorp/errwrap v1.1.0 // indirect
	github.com/hashicorp/go-cleanhttp v0.5.2 // indirect
	github.com/hashicorp/go-getter v1.8.2 // indirect
	github.com/hashicorp/go-getter/v2 v2.2.3 // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/hashicorp/go-retryablehttp v0.7.8 // indirect
	github.com/hashicorp/go-rootcerts v1.0.2 // indirect
	github.com/hashicorp/go-safetemp v1.0.0 // indirect
	github.com/hashicorp/go-secure-stdlib/parseutil v0.2.0 // indirect
	github.com/hashicorp/go-secure-stdlib/strutil v0.1.2 // indirect
	github.com/hashicorp/go-slug v0.16.8 // indirect
	github.com/hashicorp/go-sockaddr v1.0.7 // indirect
	github.com/hashicorp/go-tfe v1.95.0 // indirect
	github.com/hashicorp/go-version v1.7.0 // indirect
	github.com/hashicorp/golang-lru v1.0.2 // indirect
	github.com/hashicorp/hcl v1.0.1-vault-7 // indirect
	github.com/hashicorp/hcl/v2 v2.24.0 // indirect
	github.com/hashicorp/hcp-sdk-go v0.162.0 // indirect
	github.com/hashicorp/jsonapi v1.5.0 // indirect
	github.com/hashicorp/vault/api v1.22.0 // indirect
	github.com/helmfile/chartify v0.25.0 // indirect
	github.com/helmfile/helmfile v1.1.7 // indirect
	github.com/helmfile/vals v0.42.4 // indirect
	github.com/hexdigest/gowrap v1.4.3 // indirect
	github.com/hexops/gotextdiff v1.0.3 // indirect
	github.com/hidetatz/kubecolor v0.0.25 // indirect
	github.com/hokaccha/go-prettyjson v0.0.0-20211117102719-0474bc63780f // indirect
	github.com/huandu/xstrings v1.5.0 // indirect
	github.com/ianlancetaylor/demangle v0.0.0-20250628045327-2d64ad6b7ec5 // indirect
	github.com/inconshreveable/go-update v0.0.0-20160112193335-8152e7eb6ccf // indirect
	github.com/inconshreveable/mousetrap v1.1.0 // indirect
	github.com/incu6us/goimports-reviser v0.1.6 // indirect
	github.com/influxdata/tdigest v0.0.1 // indirect
	github.com/insomniacslk/dhcp v0.0.0-20251007151141-da879a2c3546 // indirect
	github.com/instrumenta/kubeval v0.16.1 // indirect
	github.com/invopop/jsonschema v0.13.0 // indirect
	github.com/isaacphi/mcp-language-server v0.1.1 // indirect
	github.com/itchyny/gojq v0.12.17 // indirect
	github.com/itchyny/timefmt-go v0.1.7 // indirect
	github.com/jbenet/go-context v0.0.0-20150711004518-d14ea06fba99 // indirect
	github.com/jdx/go-netrc v1.0.0 // indirect
	github.com/jedib0t/go-pretty/v6 v6.6.8 // indirect
	github.com/jhump/protoreflect v1.17.0 // indirect
	github.com/jinzhu/configor v1.2.2 // indirect
	github.com/jmespath/go-jmespath v0.4.0 // indirect
	github.com/jmoiron/sqlx v1.4.0 // indirect
	github.com/joho/godotenv v1.5.1 // indirect
	github.com/jonboulle/clockwork v0.5.0 // indirect
	github.com/josharian/impl v1.4.0 // indirect
	github.com/josharian/intern v1.0.0 // indirect
	github.com/josharian/native v1.1.0 // indirect
	github.com/jsimonetti/rtnetlink/v2 v2.0.5 // indirect
	github.com/json-iterator/go v1.1.12 // indirect
	github.com/jstemmer/gotags v1.4.1 // indirect
	github.com/k0kubun/pp v3.0.1+incompatible // indirect
	github.com/kballard/go-shellquote v0.0.0-20180428030007-95032a82bc51 // indirect
	github.com/kevinburke/ssh_config v1.4.0 // indirect
	github.com/kisielk/errcheck v1.9.0 // indirect
	github.com/kisielk/gotool v1.0.0 // indirect
	github.com/klauspost/compress v1.18.0 // indirect
	github.com/klauspost/cpuid/v2 v2.3.0 // indirect
	github.com/klauspost/pgzip v1.2.6 // indirect
	github.com/koron/iferr v0.0.0-20240122035601-9c3e2fbe4bd1 // indirect
	github.com/ktr0731/evans v0.10.11 // indirect
	github.com/ktr0731/go-multierror v0.0.0-20171204182908-b7773ae21874 // indirect
	github.com/ktr0731/go-prompt v0.2.4 // indirect
	github.com/ktr0731/go-shellstring v0.1.3 // indirect
	github.com/ktr0731/go-updater v0.1.6 // indirect
	github.com/ktr0731/grpc-web-go-client v0.2.8 // indirect
	github.com/kylelemons/godebug v1.1.0 // indirect
	github.com/lann/builder v0.0.0-20180802200727-47ae307949d0 // indirect
	github.com/lann/ps v0.0.0-20150810152359-62de8c46ede0 // indirect
	github.com/leodido/go-urn v1.4.0 // indirect
	github.com/lib/pq v1.10.9 // indirect
	github.com/liggitt/tabwriter v0.0.0-20181228230101-89fcab3d43de // indirect
	github.com/lmittmann/tint v1.1.2 // indirect
	github.com/lucasb-eyer/go-colorful v1.3.0 // indirect
	github.com/mailru/easyjson v0.9.1 // indirect
	github.com/manifoldco/promptui v0.9.0 // indirect
	github.com/mark3labs/mcp-go v0.41.1 // indirect
	github.com/mattiamari/reddit2wallpaper v0.2.3 // indirect
	github.com/mattn/efm-langserver v0.0.54 // indirect
	github.com/mattn/go-colorable v0.1.14 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/mattn/go-pipeline v0.0.0-20190323144519-32d779b32768 // indirect
	github.com/mattn/go-runewidth v0.0.19 // indirect
	github.com/mattn/go-sqlite3 v1.14.32 // indirect
	github.com/mattn/go-tty v0.0.7 // indirect
	github.com/mattn/go-unicodeclass v0.0.2 // indirect
	github.com/mdlayher/ethtool v0.5.0 // indirect
	github.com/mdlayher/genetlink v1.3.2 // indirect
	github.com/mdlayher/netlink v1.8.0 // indirect
	github.com/mdlayher/socket v0.5.1 // indirect
	github.com/mfridman/tparse v0.18.0 // indirect
	github.com/mgutz/ansi v0.0.0-20200706080929-d51e80ef957d // indirect
	github.com/mitchellh/colorstring v0.0.0-20190213212951-d06e56a500db // indirect
	github.com/mitchellh/copystructure v1.2.0 // indirect
	github.com/mitchellh/go-homedir v1.1.0 // indirect
	github.com/mitchellh/go-testing-interface v1.14.1 // indirect
	github.com/mitchellh/go-wordwrap v1.0.1 // indirect
	github.com/mitchellh/hashstructure/v2 v2.0.2 // indirect
	github.com/mitchellh/mapstructure v1.5.0 // indirect
	github.com/mitchellh/reflectwalk v1.0.2 // indirect
	github.com/mkimuram/k8sviz v0.0.0-20220606153231-7cc35701845e // indirect
	github.com/moby/docker-image-spec v1.3.1 // indirect
	github.com/moby/spdystream v0.5.0 // indirect
	github.com/moby/term v0.5.2 // indirect
	github.com/modern-go/concurrent v0.0.0-20180306012644-bacd9c7ef1dd // indirect
	github.com/modern-go/reflect2 v1.0.3-0.20250322232337-35a7c28c31ee // indirect
	github.com/momotaro98/strictgoimports v1.2.2 // indirect
	github.com/monochromegane/dragon-imports v0.0.0-20190718161134-88500cb3fd10 // indirect
	github.com/monochromegane/go-gitignore v0.0.0-20200626010858-205db1a8cc00 // indirect
	github.com/morikuni/aec v1.0.0 // indirect
	github.com/motemen/go-colorine v0.0.0-20180816141035-45d19169413a // indirect
	github.com/muesli/duf v0.9.1 // indirect
	github.com/muesli/mango v0.2.0 // indirect
	github.com/muesli/roff v0.1.0 // indirect
	github.com/muesli/termenv v0.16.0 // indirect
	github.com/munnerz/goautoneg v0.0.0-20191010083416-a7dc8b61c822 // indirect
	github.com/mxk/go-flowrate v0.0.0-20140419014527-cca7078d478f // indirect
	github.com/nsf/gocode v0.0.0-20230322162601-b672b49f3818 // indirect
	github.com/nsf/termbox-go v1.1.1 // indirect
	github.com/oasisprotocol/curve25519-voi v0.0.0-20230904125328-1f23a7beb09a // indirect
	github.com/oklog/ulid v1.3.1 // indirect
	github.com/olekukonko/cat v0.0.0-20250911104152-50322a0618f6 // indirect
	github.com/olekukonko/errors v1.1.0 // indirect
	github.com/olekukonko/ll v0.1.2 // indirect
	github.com/olekukonko/tablewriter v1.1.0 // indirect
	github.com/opencontainers/go-digest v1.0.0 // indirect
	github.com/opencontainers/image-spec v1.1.1 // indirect
	github.com/opencontainers/runtime-spec v1.2.1 // indirect
	github.com/opentracing/opentracing-go v1.2.0 // indirect
	github.com/orisano/dlayer v0.3.1 // indirect
	github.com/otiai10/copy v1.14.1 // indirect
	github.com/otiai10/mint v1.6.3 // indirect
	github.com/pelletier/go-toml v1.9.5 // indirect
	github.com/pelletier/go-toml/v2 v2.2.4 // indirect
	github.com/peterbourgon/diskv v2.0.1+incompatible // indirect
	github.com/petermattis/goid v0.0.0-20250904145737-900bdf8bb490 // indirect
	github.com/pierrec/lz4/v4 v4.1.22 // indirect
	github.com/pin/tftp/v3 v3.1.0 // indirect
	github.com/pjbgf/sha1cd v0.5.0 // indirect
	github.com/pkg/browser v0.0.0-20240102092130-5ac0b6a4141c // indirect
	github.com/pkg/errors v0.9.1 // indirect
	github.com/pkg/profile v1.7.0 // indirect
	github.com/pkg/term v1.2.0-beta.2 // indirect
	github.com/planetscale/vtprotobuf v0.6.1-0.20241121165744-79df5c4772f2 // indirect
	github.com/pmezard/go-difflib v1.0.1-0.20181226105442-5d4384ee4fb2 // indirect
	github.com/prometheus/client_golang v1.23.2 // indirect
	github.com/prometheus/client_model v0.6.2 // indirect
	github.com/prometheus/common v0.67.1 // indirect
	github.com/prometheus/procfs v0.17.0 // indirect
	github.com/puzpuzpuz/xsync/v3 v3.5.1 // indirect
	github.com/pwaller/goimports-update-ignore v0.0.0-20170215205638-d2c92f72b3de // indirect
	github.com/quasilyte/go-ruleguard v0.4.5 // indirect
	github.com/quasilyte/gogrep v0.5.0 // indirect
	github.com/quasilyte/stdinfo v0.0.0-20220114132959-f7386bf02567 // indirect
	github.com/quic-go/qpack v0.5.1 // indirect
	github.com/quic-go/quic-go v0.55.0 // indirect
	github.com/rerost/dragon-imports v0.0.0-20200512170120-c6226dfec3a1 // indirect
	github.com/reviewdog/errorformat v0.0.0-20250320004447-223c26dbe212 // indirect
	github.com/rivo/tview v0.42.0 // indirect
	github.com/rivo/uniseg v0.4.7 // indirect
	github.com/rogpeppe/go-internal v1.14.1 // indirect
	github.com/rs/cors v1.11.1 // indirect
	github.com/rs/xid v1.6.0 // indirect
	github.com/rs/zerolog v1.34.0 // indirect
	github.com/rubenv/sql-migrate v1.8.0 // indirect
	github.com/russross/blackfriday/v2 v2.1.0 // indirect
	github.com/ryanuber/columnize v2.1.2+incompatible // indirect
	github.com/ryanuber/go-glob v1.0.0 // indirect
	github.com/sabhiram/go-gitignore v0.0.0-20210923224102-525f6e181f06 // indirect
	github.com/sagikazarmark/locafero v0.12.0 // indirect
	github.com/sajari/fuzzy v1.0.0 // indirect
	github.com/santhosh-tekuri/jsonschema/v6 v6.0.2 // indirect
	github.com/saracen/walker v0.1.4 // indirect
	github.com/sasha-s/go-deadlock v0.3.6 // indirect
	github.com/scaleway/scaleway-sdk-go v1.0.0-beta.35 // indirect
	github.com/securego/gosec/v2 v2.22.10 // indirect
	github.com/segmentio/asm v1.2.1 // indirect
	github.com/segmentio/encoding v0.5.3 // indirect
	github.com/sergi/go-diff v1.4.0 // indirect
	github.com/shopspring/decimal v1.4.0 // indirect
	github.com/siderolabs/crypto v0.6.4 // indirect
	github.com/siderolabs/gen v0.8.5 // indirect
	github.com/siderolabs/go-api-signature v0.3.9 // indirect
	github.com/siderolabs/go-blockdevice/v2 v2.0.19 // indirect
	github.com/siderolabs/go-circular v0.2.3 // indirect
	github.com/siderolabs/go-cmd v0.1.3 // indirect
	github.com/siderolabs/go-kubeconfig v0.1.1 // indirect
	github.com/siderolabs/go-kubernetes v0.2.26 // indirect
	github.com/siderolabs/go-loadbalancer v0.5.0 // indirect
	github.com/siderolabs/go-pointer v1.0.1 // indirect
	github.com/siderolabs/go-procfs v0.1.2 // indirect
	github.com/siderolabs/go-retry v0.3.3 // indirect
	github.com/siderolabs/go-talos-support v0.1.2 // indirect
	github.com/siderolabs/kms-client v0.1.0 // indirect
	github.com/siderolabs/net v0.4.0 // indirect
	github.com/siderolabs/proto-codec v0.1.2 // indirect
	github.com/siderolabs/protoenc v0.2.4 // indirect
	github.com/siderolabs/siderolink v0.3.15 // indirect
	github.com/siderolabs/talos v1.11.3 // indirect
	github.com/siderolabs/talos/pkg/machinery v1.11.3 // indirect
	github.com/siderolabs/tcpproxy v0.1.0 // indirect
	github.com/sirupsen/logrus v1.9.3 // indirect
	github.com/skeema/knownhosts v1.3.2 // indirect
	github.com/skratchdot/open-golang v0.0.0-20200116055534-eef842397966 // indirect
	github.com/sosodev/duration v1.3.1 // indirect
	github.com/sourcegraph/jsonrpc2 v0.2.1 // indirect
	github.com/spf13/afero v1.15.0 // indirect
	github.com/spf13/cast v1.10.0 // indirect
	github.com/spf13/cobra v1.10.1 // indirect
	github.com/spf13/pflag v1.0.10 // indirect
	github.com/spf13/viper v1.21.0 // indirect
	github.com/spiffe/go-spiffe/v2 v2.6.0 // indirect
	github.com/sqs/goreturns v0.0.0-20231030191505-16fc3d8edd91 // indirect
	github.com/stoewer/go-strcase v1.3.1 // indirect
	github.com/streadway/quantile v0.0.0-20220407130108-4246515d968d // indirect
	github.com/stretchr/objx v0.5.3 // indirect
	github.com/stretchr/testify v1.11.1 // indirect
	github.com/subosito/gotenv v1.6.0 // indirect
	github.com/tatsushid/go-prettytable v0.0.0-20141013043238-ed2d14c29939 // indirect
	github.com/tendermint/tendermint v0.35.9 // indirect
	github.com/tetratelabs/wabin v0.0.0-20230304001439-f6f874872834 // indirect
	github.com/tetratelabs/wazero v1.9.0 // indirect
	github.com/tidwall/gjson v1.18.0 // indirect
	github.com/tidwall/match v1.2.0 // indirect
	github.com/tidwall/pretty v1.2.1 // indirect
	github.com/tidwall/sjson v1.2.5 // indirect
	github.com/tj/go-spin v1.1.0 // indirect
	github.com/tsenart/go-tsz v0.0.0-20180814235614-0bd30b3df1c3 // indirect
	github.com/tsenart/vegeta v12.7.0+incompatible // indirect
	github.com/twitchyliquid64/golang-asm v0.15.1 // indirect
	github.com/u-root/u-root v0.15.0 // indirect
	github.com/u-root/uio v0.0.0-20240224005618-d2acac8f3701 // indirect
	github.com/uber/jaeger-client-go v2.30.0+incompatible // indirect
	github.com/uber/jaeger-lib v2.4.1+incompatible // indirect
	github.com/uber/prototool v1.10.0 // indirect
	github.com/ugorji/go/codec v1.3.0 // indirect
	github.com/ulikunitz/xz v0.5.15 // indirect
	github.com/urfave/cli v1.22.17 // indirect
	github.com/urfave/cli/v2 v2.27.7 // indirect
	github.com/variantdev/dag v1.1.0 // indirect
	github.com/vbatts/tar-split v0.12.2 // indirect
	github.com/vektah/gqlparser/v2 v2.5.30 // indirect
	github.com/vishvananda/netlink v1.3.1 // indirect
	github.com/vishvananda/netns v0.0.5 // indirect
	github.com/vugu/vgrun v0.0.0-20221010231011-b56916c1e8c2 // indirect
	github.com/wk8/go-ordered-map/v2 v2.1.8 // indirect
	github.com/x-motemen/ghq v1.8.0 // indirect
	github.com/x448/float16 v0.8.4 // indirect
	github.com/xanzy/ssh-agent v0.3.3 // indirect
	github.com/xeipuuv/gojsonpointer v0.0.0-20190905194746-02993c407bfb // indirect
	github.com/xeipuuv/gojsonreference v0.0.0-20180127040603-bd5ef7bd5415 // indirect
	github.com/xeipuuv/gojsonschema v1.2.0 // indirect
	github.com/xi2/xz v0.0.0-20171230120015-48954b6210f8 // indirect
	github.com/xiang90/probing v0.0.0-20221125231312-a49e3df8f510 // indirect
	github.com/xlab/treeprint v1.2.0 // indirect
	github.com/xo/terminfo v0.0.0-20220910002029-abceb7e1c41e // indirect
	github.com/xrash/smetrics v0.0.0-20250705151800-55b8f293f342 // indirect
	github.com/y4v8/gojson v1.1.0 // indirect
	github.com/yandex-cloud/go-genproto v0.30.0 // indirect
	github.com/yandex-cloud/go-sdk v0.24.0 // indirect
	github.com/yannh/kubeconform v0.7.0 // indirect
	github.com/yosida95/uritemplate/v3 v3.0.2 // indirect
	github.com/yuin/goldmark v1.7.13 // indirect
	github.com/zalando/go-keyring v0.2.6 // indirect
	github.com/zchee/go-xdgbasedir v1.0.3 // indirect
	github.com/zclconf/go-cty v1.17.0 // indirect
	github.com/zclconf/go-cty-yaml v1.1.0 // indirect
	github.com/zeebo/xxh3 v1.0.2 // indirect
	go.etcd.io/bbolt v1.4.3 // indirect
	go.etcd.io/etcd/api/v3 v3.6.5 // indirect
	go.etcd.io/etcd/client/pkg/v3 v3.6.5 // indirect
	go.etcd.io/etcd/client/v3 v3.6.5 // indirect
	go.etcd.io/etcd/etcdutl/v3 v3.6.5 // indirect
	go.etcd.io/etcd/pkg/v3 v3.6.5 // indirect
	go.etcd.io/etcd/server/v3 v3.6.5 // indirect
	go.etcd.io/raft/v3 v3.6.0 // indirect
	go.lsp.dev/jsonrpc2 v0.10.0 // indirect
	go.lsp.dev/pkg v0.0.0-20210717090340-384b27a52fb2 // indirect
	go.lsp.dev/protocol v0.12.0 // indirect
	go.lsp.dev/uri v0.3.0 // indirect
	go.mongodb.org/mongo-driver v1.17.4 // indirect
	go.opentelemetry.io/auto/sdk v1.2.1 // indirect
	go.opentelemetry.io/contrib/detectors/gcp v1.38.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc v0.63.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.63.0 // indirect
	go.opentelemetry.io/otel v1.38.0 // indirect
	go.opentelemetry.io/otel/metric v1.38.0 // indirect
	go.opentelemetry.io/otel/sdk v1.38.0 // indirect
	go.opentelemetry.io/otel/sdk/metric v1.38.0 // indirect
	go.opentelemetry.io/otel/trace v1.38.0 // indirect
	go.opentelemetry.io/proto/otlp v1.8.0 // indirect
	go.starlark.net v0.0.0-20250906160240-bf296ed553ea // indirect
	go.szostok.io/version v1.2.0 // indirect
	go.uber.org/atomic v1.11.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/zap v1.27.0 // indirect
	go.yaml.in/yaml/v2 v2.4.3 // indirect
	go.yaml.in/yaml/v3 v3.0.4 // indirect
	go4.org/netipx v0.0.0-20231129151722-fdeea329fbba // indirect
	golang.org/dl v0.0.0-20251013210724-90b1a3fbfb96 // indirect
	golang.org/x/arch v0.22.0 // indirect
	golang.org/x/crypto v0.43.0 // indirect
	golang.org/x/exp v0.0.0-20251009144603-d2f985daa21b // indirect
	golang.org/x/exp/typeparams v0.0.0-20251009144603-d2f985daa21b // indirect
	golang.org/x/lint v0.0.0-20241112194109-818c5a804067 // indirect
	golang.org/x/mod v0.29.0 // indirect
	golang.org/x/net v0.46.0 // indirect
	golang.org/x/oauth2 v0.32.0 // indirect
	golang.org/x/review v1.17.0 // indirect
	golang.org/x/sync v0.17.0 // indirect
	golang.org/x/sys v0.37.0 // indirect
	golang.org/x/telemetry v0.0.0-20251014153721-24f779f6aaef // indirect
	golang.org/x/term v0.36.0 // indirect
	golang.org/x/text v0.30.0 // indirect
	golang.org/x/time v0.14.0 // indirect
	golang.org/x/tools v0.38.0 // indirect
	golang.org/x/tools/cmd/godoc v0.1.0-deprecated // indirect
	golang.org/x/tools/godoc v0.1.0-deprecated // indirect
	golang.org/x/vuln v1.1.4 // indirect
	golang.zx2c4.com/wintun v0.0.0-20230126152724-0fa3db229ce2 // indirect
	golang.zx2c4.com/wireguard v0.0.0-20250521234502-f333402bd9cb // indirect
	golang.zx2c4.com/wireguard/wgctrl v0.0.0-20241231184526-a9ab2273dd10 // indirect
	google.golang.org/api v0.252.0 // indirect
	google.golang.org/genai v1.31.0 // indirect
	google.golang.org/genproto v0.0.0-20251014184007-4626949a642f // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20251014184007-4626949a642f // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20251014184007-4626949a642f // indirect
	google.golang.org/grpc v1.76.0 // indirect
	google.golang.org/protobuf v1.36.10 // indirect
	gopkg.in/evanphx/json-patch.v4 v4.13.0 // indirect
	gopkg.in/gookit/color.v1 v1.1.6 // indirect
	gopkg.in/inf.v0 v0.9.1 // indirect
	gopkg.in/ini.v1 v1.67.0 // indirect
	gopkg.in/warnings.v0 v0.1.2 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
	helm.sh/helm/v3 v3.19.0 // indirect
	k8s.io/api v0.34.1 // indirect
	k8s.io/apiextensions-apiserver v0.34.1 // indirect
	k8s.io/apimachinery v0.34.1 // indirect
	k8s.io/cli-runtime v0.34.1 // indirect
	k8s.io/client-go v0.34.1 // indirect
	k8s.io/component-base v0.34.1 // indirect
	k8s.io/klog/v2 v2.130.1 // indirect
	k8s.io/kube-openapi v0.0.0-20250910181357-589584f1c912 // indirect
	k8s.io/kubectl v0.34.1 // indirect
	k8s.io/utils v0.0.0-20251002143259-bc988d571ff4 // indirect
	mvdan.cc/editorconfig v0.3.0 // indirect
	mvdan.cc/gofumpt v0.9.1 // indirect
	mvdan.cc/sh/moreinterp v0.0.0-20250915182820-b717ad599e17 // indirect
	mvdan.cc/sh/v3 v3.12.0 // indirect
	oras.land/oras-go/v2 v2.6.0 // indirect
	pluginrpc.com/pluginrpc v0.5.0 // indirect
	sigs.k8s.io/hydrophone v0.7.0 // indirect
	sigs.k8s.io/json v0.0.0-20250730193827-2d320260d730 // indirect
	sigs.k8s.io/kind v0.30.0 // indirect
	sigs.k8s.io/knftables v0.0.19 // indirect
	sigs.k8s.io/kubectl-check-ownerreferences v0.4.0 // indirect
	sigs.k8s.io/kustomize/api v0.20.1 // indirect
	sigs.k8s.io/kustomize/cmd/config v0.20.1 // indirect
	sigs.k8s.io/kustomize/kustomize/v5 v5.7.1 // indirect
	sigs.k8s.io/kustomize/kyaml v0.20.1 // indirect
	sigs.k8s.io/randfill v1.0.0 // indirect
	sigs.k8s.io/structured-merge-diff/v6 v6.3.0 // indirect
	sigs.k8s.io/yaml v1.6.0 // indirect
)
