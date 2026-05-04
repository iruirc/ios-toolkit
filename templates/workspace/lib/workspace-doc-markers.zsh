#!/usr/bin/env zsh
# workspace-doc-markers.zsh — parse + replace WORKSPACE_*_BEGIN / _END regions.

wsmark::read() {
  local file="$1" name="$2"
  if [[ -z "$file" || -z "$name" ]]; then
    print -u2 "wsmark::read: usage: <file> <marker-name>"
    return 4
  fi
  if [[ ! -r "$file" ]]; then
    print -u2 "wsmark::read: cannot read $file"
    return 4
  fi
  local begin="<!-- WORKSPACE_${name}_BEGIN -->"
  local end="<!-- WORKSPACE_${name}_END -->"
  awk -v b="$begin" -v e="$end" '
    BEGIN { inside = 0; found = 0 }
    $0 == b { inside = 1; found++; next }
    $0 == e { inside = 0; next }
    inside { print }
    END { if (found != 1) exit 2 }
  ' "$file"
}

wsmark::write() {
  local file="$1" name="$2"
  if [[ -z "$file" || -z "$name" ]]; then
    print -u2 "wsmark::write: usage: <file> <marker-name> (content via stdin)"
    return 4
  fi
  if [[ ! -r "$file" || ! -w "$file" ]]; then
    print -u2 "wsmark::write: cannot read+write $file"
    return 4
  fi
  local begin="<!-- WORKSPACE_${name}_BEGIN -->"
  local end="<!-- WORKSPACE_${name}_END -->"
  local new_content
  new_content="$(cat -)"
  local tmp
  tmp="$(mktemp -t wsmark.XXXXXX)" || return 4
  awk -v b="$begin" -v e="$end" -v nc="$new_content" '
    BEGIN { inside = 0 }
    $0 == b { print; print nc; inside = 1; next }
    $0 == e { print; inside = 0; next }
    inside { next }
    { print }
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 4; }
  mv -- "$tmp" "$file"
  return 0
}

wsmark::lint() {
  local file="$1"
  if [[ ! -r "$file" ]]; then
    print -u2 "wsmark::lint: cannot read $file"
    return 4
  fi
  local errs=0
  local -a open_stack open_lines
  local lineno=0 line name top i
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((lineno++))
    if [[ "$line" =~ '^<!-- WORKSPACE_([A-Z_]+)_BEGIN -->$' ]]; then
      name="${match[1]}"
      # duplicate BEGIN of same name?
      for ((i=1; i<=${#open_stack[@]}; i++)); do
        if [[ "${open_stack[$i]}" == "$name" ]]; then
          print -u2 "$file:$lineno: duplicate WORKSPACE_${name}_BEGIN (previous at line ${open_lines[$i]})"
          ((errs++))
          break
        fi
      done
      open_stack+=("$name")
      open_lines+=("$lineno")
    elif [[ "$line" =~ '^<!-- WORKSPACE_([A-Z_]+)_END -->$' ]]; then
      name="${match[1]}"
      if (( ${#open_stack[@]} == 0 )); then
        print -u2 "$file:$lineno: orphan WORKSPACE_${name}_END (no matching _BEGIN)"
        ((errs++))
      else
        top="${open_stack[-1]}"
        if [[ "$top" != "$name" ]]; then
          print -u2 "$file:$lineno: marker WORKSPACE_${name}_END crosses WORKSPACE_${top} boundary"
          ((errs++))
          # pop until match found or stack empty
          while (( ${#open_stack[@]} > 0 )) && [[ "${open_stack[-1]}" != "$name" ]]; do
            open_stack[-1]=()
            open_lines[-1]=()
          done
        fi
        if (( ${#open_stack[@]} > 0 )); then
          open_stack[-1]=()
          open_lines[-1]=()
        fi
      fi
    fi
  done < "$file"
  # any remaining opens = missing END
  for ((i=1; i<=${#open_stack[@]}; i++)); do
    print -u2 "$file:${open_lines[$i]}: missing WORKSPACE_${open_stack[$i]}_END for opener"
    ((errs++))
  done
  if (( errs > 0 )); then
    print -u2 "$errs marker error(s)."
    return 2
  fi
  return 0
}

wsmark::repair() {
  local file tmp lineno line name top resp m i found
  file="$1"
  if [[ ! -r "$file" || ! -w "$file" ]]; then
    print -u2 "wsmark::repair: cannot read+write $file"
    return 4
  fi
  # Build a repaired version into a temp file by replaying the parse with fixups.
  tmp="$(mktemp -t wsmark-repair.XXXXXX)" || return 4
  local -a open_stack
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((lineno++))
    if [[ "$line" =~ '^<!-- WORKSPACE_([A-Z_]+)_BEGIN -->$' ]]; then
      name="${match[1]}"
      # drop duplicate BEGIN of same name
      found=0
      for ((i=1; i<=${#open_stack[@]}; i++)); do
        if [[ "${open_stack[$i]}" == "$name" ]]; then found=1; break; fi
      done
      if (( found )); then
        # Skip duplicate marker (do not write)
        continue
      fi
      open_stack+=("$name")
      print -r -- "$line" >> "$tmp"
    elif [[ "$line" =~ '^<!-- WORKSPACE_([A-Z_]+)_END -->$' ]]; then
      name="${match[1]}"
      if (( ${#open_stack[@]} == 0 )); then
        # Orphan END — drop it
        continue
      fi
      top="${open_stack[-1]}"
      if [[ "$top" != "$name" ]]; then
        # Cross-nested END — refuse auto-repair, keep file unchanged + bail
        print -u2 "wsmark::repair: cannot auto-repair cross-nested boundary at line $lineno"
        rm -f "$tmp"
        return 2
      fi
      open_stack[-1]=()
      print -r -- "$line" >> "$tmp"
    else
      print -r -- "$line" >> "$tmp"
    fi
  done < "$file"
  # Close any remaining open markers
  while (( ${#open_stack[@]} > 0 )); do
    m="${open_stack[-1]}"
    print -r -- "<!-- WORKSPACE_${m}_END -->" >> "$tmp"
    open_stack[-1]=()
  done
  print "Proposed changes to $file:"
  diff -u "$file" "$tmp" || true
  print -n "Apply? (y/N) "
  read -r resp
  if [[ "$resp" != "y" && "$resp" != "Y" ]]; then
    rm -f "$tmp"
    return 1
  fi
  mv -- "$tmp" "$file"
  return 0
}
