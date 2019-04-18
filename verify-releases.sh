#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

ehcache3_repo_url="git@github.com:ehcache/ehcache3.git"
jardiff_jar_url="https://github.com/scala/jardiff/releases/download/v1.2.0/jardiff.jar"
maven_repo_url="https://repo.maven.apache.org/maven2"
versions=(
   3.0.0 3.0.1 3.0.2 3.0.3
   3.1.0 3.1.1 3.1.2 3.1.3 3.1.4
   3.2.0 3.2.1 3.2.2 3.2.3
   3.3.0 3.3.1 3.3.2
   3.4.0
   3.5.0 3.5.1 3.5.2 3.5.3
   3.6.0 3.6.1 3.6.2 3.6.3
   3.7.0 3.7.1
)

#Force early resolution of required environment variables
[[ -e ${JAVA_HOME_6} ]]
[[ -e ${JAVA_HOME_8} ]]

function diffJar {
  untrusted="${2%.*}.untrusted.${2##*.}"
  if ! [[ -f ${untrusted} ]]; then
    curl -L "${3}" --output "${untrusted}"
  fi
  java -jar ../../utilities/jardiff.jar "${2}" "${untrusted}" > "../../artifact-diffs/${1}.diff" || true
}

if ! [[ -e sources/ehcache3 ]]; then git clone ${ehcache3_repo_url} sources/ehcache3; fi

mkdir utilities || true
if ! [[ -f utilities/jardiff.jar ]]; then curl -L ${jardiff_jar_url} --output utilities/jardiff.jar; fi

for version in ${versions[@]}; do
  source="sources/${version}"
  tag="v${version}"
  patch="patches/${version}.patch"

  if ! [[ -e "${source}" ]]; then git -C sources/ehcache3/ worktree add "../../${source}" "${tag}"; fi

  if [[ -f "${patch}" ]]
  then
    git -C "${source}" reset --hard "${tag}"
    git -C "${source}" apply "../../${patch}"
  else
    git -C "${source}" merge --no-commit 123319cc6b42238e7a006c12aef9732f40d45dda
  fi
  if ! [[ -z $(git -C "${source}" status --porcelain) ]]; then git -C "${source}" commit -am "switching to secure dependency fetching"; fi

  pushd ${source}
    case ${version} in
    3.0.?|3.1.0|3.1.1|3.1.2|3.1.3)
        # Fetch dependencies using Java 8 since Java 6 VMs that support TLS 1.2 are rare (i.e. expensive)
        JAVA_HOME="${JAVA_HOME_8}" ./gradlew --refresh-dependencies assemble
        # Fetch the 1.6 specific version of findbugs annotations through this ugly hack
        JAVA_HOME="${JAVA_HOME_8}" ./gradlew --refresh-dependencies -p ../../patches/dependency-hack -Pdependency=com.google.code.findbugs:annotations:2.0.3 fetch
        JAVA_HOME="${JAVA_HOME_6}" ./gradlew --offline clean assemble
        ;;
    3.5.0|3.5.1|3.5.2)
        # building docs is broken in these tags due to rubygems.lasagna.io disappearing
        JAVA_HOME="${JAVA_HOME_8}" ./gradlew --refresh-dependencies assemble -x :docs:asciidoctor -x :clustered:clustered-dist:distZip -x :clustered:clustered-dist:distTar
        ;;
    *)
        JAVA_HOME="${JAVA_HOME_8}" ./gradlew --refresh-dependencies assemble
        ;;
    esac

    mkdir -p "../../artifact-diffs/${version}"
    case ${version} in
    3.0.?)
        diffJar "${version}/ehcache-107" "107/build/libs/ehcache-107-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-107/${version}/ehcache-107-${version}.jar"
        diffJar "${version}/ehcache-api" "api/build/libs/ehcache-api-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-api/${version}/ehcache-api-${version}.jar"

        diffJar "${version}/ehcache-core" "core/build/libs/ehcache-core-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-core/${version}/ehcache-core-${version}.jar"
        diffJar "${version}/ehcache-impl" "impl/build/libs/ehcache-impl-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-impl/${version}/ehcache-impl-${version}.jar"

        diffJar "${version}/ehcache-management" "management/build/libs/ehcache-management-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-management/${version}/ehcache-management-${version}.jar"
        diffJar "${version}/ehcache-xml" "xml/build/libs/ehcache-xml-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-xml/${version}/ehcache-xml-${version}.jar"

        # For 3.0.x releases transactions was under 'modules'
        diffJar "${version}/ehcache-transactions" "transactions/build/libs/ehcache-transactions-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-transactions/${version}/ehcache-transactions-${version}.jar"

        diffJar "${version}/ehcache" "dist/build/libs/ehcache-${version}.jar" "${maven_repo_url}/org/ehcache/ehcache/${version}/ehcache-${version}.jar"
        ;;
    *)
        diffJar "${version}/ehcache-107" "107/build/libs/ehcache-107-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-107/${version}/ehcache-107-${version}.jar"
        diffJar "${version}/ehcache-api" "api/build/libs/ehcache-api-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-api/${version}/ehcache-api-${version}.jar"
        diffJar "${version}/ehcache-client" "clustered/client/build/libs/ehcache-client-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-client/${version}/ehcache-client-${version}.jar"
        diffJar "${version}/ehcache-common" "clustered/common/build/libs/ehcache-common-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-common/${version}/ehcache-common-${version}.jar"

        diffJar "${version}/ehcache-core" "core/build/libs/ehcache-core-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-core/${version}/ehcache-core-${version}.jar"
        diffJar "${version}/ehcache-impl" "impl/build/libs/ehcache-impl-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-impl/${version}/ehcache-impl-${version}.jar"

        diffJar "${version}/ehcache-management" "management/build/libs/ehcache-management-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-management/${version}/ehcache-management-${version}.jar"
        diffJar "${version}/ehcache-server" "clustered/server/build/libs/ehcache-server-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-server/${version}/ehcache-server-${version}.jar"
        diffJar "${version}/ehcache-xml" "xml/build/libs/ehcache-xml-${version}.jar" "${maven_repo_url}/org/ehcache/modules/ehcache-xml/${version}/ehcache-xml-${version}.jar"

        diffJar "${version}/ehcache" "dist/build/libs/ehcache-${version}.jar" "${maven_repo_url}/org/ehcache/ehcache/${version}/ehcache-${version}.jar"
        diffJar "${version}/ehcache-clustered" "clustered/clustered-dist/build/libs/ehcache-clustered-${version}.jar" "${maven_repo_url}/org/ehcache/ehcache-clustered/${version}/ehcache-clustered-${version}.jar"
        diffJar "${version}/ehcache-transactions" "transactions/build/libs/ehcache-transactions-${version}.jar" "${maven_repo_url}/org/ehcache/ehcache-transactions/${version}/ehcache-transactions-${version}.jar"
        ;;
    esac
  popd
done


