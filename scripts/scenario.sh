#!/usr/bin/env bash
# Run a break-fix scenario against the kind cluster (Path B) from your WSL terminal.
#
#   scripts/scenario.sh break  <N>       inject the failure, then troubleshoot it by hand
#   scripts/scenario.sh verify <N>       grade your fix
#   scripts/scenario.sh fix    <N>       apply the reference solution (spoiler!)
#   scripts/scenario.sh test   <N|all>   self-test: break -> verify must FAIL -> fix -> verify must PASS
#
# Scenarios 03 and 04 only need kubectl, so they run right here. Scenarios 01 and 02 break a
# node, so their scripts are copied into the node container and run there as root. That's the
# kind equivalent of SSHing into the VM. On Path A (VMs), run ./break.sh on the node directly.

set -euo pipefail

SCENARIOS="$(cd "$(dirname "$0")/../05-troubleshooting-break-fix" && pwd)"

usage() { sed -n '2,7p' "$0"; exit 1; }

# The kind node a scenario has to run on (empty = run locally with kubectl)
node_for() {
  case "$1" in
    01) echo k8s-worker ;;
    02) echo k8s-control-plane ;;
    *)  echo "" ;;
  esac
}

run() {  # run <break|verify|fix> <NN>
  local step=$1 n=$2 dir node
  dir=$(echo "$SCENARIOS"/scenario-"$n"-*)
  [ -d "$dir" ] || { echo "❌ No scenario $n in $SCENARIOS"; exit 1; }
  node=$(node_for "$n")

  if [ -z "$node" ]; then
    (cd "$dir" && bash "./$step.sh")
    return
  fi

  docker cp "$dir" "$node:/root/" >/dev/null
  # Inside the node, kubectl needs the admin kubeconfig (same as on k8s-master)
  docker exec -e KUBECONFIG=/etc/kubernetes/admin.conf -w "/root/$(basename "$dir")" "$node" bash "./$step.sh"

  if [ "$step" = break ]; then
    echo "👉 Troubleshoot inside the node: docker exec -it $node bash"
  fi
}

# Re-run verify.sh until it gives the expected result. Kubernetes is eventually consistent:
# kubelet needs ~20s to notice a static pod manifest change, a rollout takes time, and so on.
# A single immediate check would be flaky.
expect() {  # expect <pass|fail> <NN>
  local want=$1 n=$2 out rc
  for _ in $(seq 1 36); do  # 36 x 5s = 3 minutes
    rc=0
    out=$(timeout 60 bash "$0" verify "$n" 2>&1) || rc=$?
    if { [ "$want" = pass ] && [ "$rc" -eq 0 ]; } || { [ "$want" = fail ] && [ "$rc" -ne 0 ]; }; then
      echo "$out" | sed 's/^/   │ /'
      return
    fi
    sleep 5
  done
  echo "❌ verify.sh never ${want}ed. Last output:"
  echo "$out"
  exit 1
}

selftest() {  # selftest <NN>
  local n=$1
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━ Self-test: Scenario $n ━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ 1/4 break.sh"
  run break "$n"
  echo "▶ 2/4 verify.sh must FAIL (proves the grader notices the breakage)"
  expect fail "$n"
  echo "▶ 3/4 fix.sh (the reference solution)"
  run fix "$n"
  echo "▶ 4/4 verify.sh must PASS (proves the solution actually fixes it)"
  expect pass "$n"
  # Leave a healthy cluster behind for the next scenario
  kubectl wait --for=condition=Ready nodes --all --timeout=180s >/dev/null
  echo "✅ Scenario $n self-test passed"
}

[ $# -eq 2 ] || usage
action=$1

if [ "$2" = all ]; then
  [ "$action" = test ] || usage
  for dir in "$SCENARIOS"/scenario-*/; do
    n=${dir#"$SCENARIOS"/scenario-}
    selftest "${n%%-*}"
  done
  exit
fi

n=$(printf '%02d' "$((10#$2))")  # accept 1 or 01
case "$action" in
  break|verify|fix) run "$action" "$n" ;;
  test)             selftest "$n" ;;
  *)                usage ;;
esac
