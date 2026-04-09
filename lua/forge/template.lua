local M = {}
local yaml_template_error =
  'tree-sitter yaml parser not found; install it to use YAML issue form templates'

---@class forge.TemplateEntry
---@field name string
---@field display string
---@field is_yaml boolean
---@field dir string

---@param s string
---@return string
function M.normalize_body(s)
  return vim.trim(s):gsub('%s+', ' ')
end

---@param branch string
---@param base string
---@return string title, string body
function M.fill_from_commits(branch, base)
  local result = vim
    .system({ 'git', 'log', 'origin/' .. base .. '..HEAD', '--format=%s%n%b%x00' }, { text = true })
    :wait()
  local raw = vim.trim(result.stdout or '')
  if raw == '' then
    local clean = branch:gsub('^%w+/', ''):gsub('[/-]', ' ')
    return clean, ''
  end

  local commits = {}
  for chunk in raw:gmatch('([^%z]+)') do
    local lines = vim.split(vim.trim(chunk), '\n', { plain = true })
    local subject = lines[1] or ''
    local body = vim.trim(table.concat(lines, '\n', 2))
    table.insert(commits, { subject = subject, body = body })
  end

  if #commits == 0 then
    local clean = branch:gsub('^%w+/', ''):gsub('[/-]', ' ')
    return clean, ''
  end

  if #commits == 1 then
    return commits[1].subject, commits[1].body
  end

  local clean = branch:gsub('^%w+/', ''):gsub('[/-]', ' ')
  local lines = {}
  for _, c in ipairs(commits) do
    table.insert(lines, '- ' .. c.subject)
  end
  return clean, table.concat(lines, '\n')
end

---@param path string
---@return string?
function M.read_file(path)
  local st = vim.uv.fs_stat(path)
  if not st then
    return nil
  end
  local fd = vim.uv.fs_open(path, 'r', 438)
  if not fd then
    return nil
  end
  local content = vim.uv.fs_read(fd, st.size, 0)
  vim.uv.fs_close(fd)
  return content
end

---@param name string
---@return boolean
function M.is_yaml(name)
  return name:match('%.ya?ml$') ~= nil
end

---@param content string
---@param yaml_file boolean
---@return forge.TemplateResult?
---@return string?
function M.make_template_result(content, yaml_file)
  if yaml_file then
    if not pcall(vim.treesitter.language.inspect, 'yaml') then
      return nil, yaml_template_error
    end
    local yaml = require('forge.yaml')
    return yaml.render(yaml.parse(content))
  end
  return { body = vim.trim(content) }
end

---@param content string
---@return string?
function M.yaml_name(content)
  for line in content:gmatch('[^\n]+') do
    local val = line:match('^name:%s+(.+)')
    if val then
      val = vim.trim(val)
      if #val >= 2 and (val:sub(1, 1) == "'" or val:sub(1, 1) == '"') then
        val = val:sub(2, -2)
      end
      return val
    end
  end
  return nil
end

---@param paths string[]
---@param repo_root string
---@return forge.TemplateResult? result
---@return forge.TemplateEntry[]? templates
---@return string? err
function M.discover(paths, repo_root)
  local log = require('forge.logger')
  local t0 = vim.uv.hrtime()
  for _, p in ipairs(paths) do
    local full = repo_root .. '/' .. p
    local stat = vim.uv.fs_stat(full)
    if stat and stat.type == 'file' then
      local content = M.read_file(full)
      if content then
        log.debug(('template: %s (%.1fms)'):format(p, (vim.uv.hrtime() - t0) / 1e6))
        local result, err = M.make_template_result(content, M.is_yaml(p))
        return result, nil, err
      end
    elseif stat and stat.type == 'directory' then
      local handle = vim.uv.fs_scandir(full)
      if handle then
        ---@type forge.TemplateEntry[]
        local templates = {}
        while true do
          local name, typ = vim.uv.fs_scandir_next(handle)
          if not name then
            break
          end
          local is_md = name:match('%.md$')
          local is_yml = M.is_yaml(name) and not name:match('^config%.ya?ml$')
          if (typ == 'file' or not typ) and (is_md or is_yml) then
            local display = name
            if is_yml then
              local content = M.read_file(full .. '/' .. name)
              if content then
                display = M.yaml_name(content) or name
              end
            end
            table.insert(templates, {
              name = name,
              display = display,
              is_yaml = is_yml ~= nil,
              dir = full,
            })
          end
        end
        if #templates == 1 then
          local content = M.read_file(full .. '/' .. templates[1].name)
          if content then
            local result, err = M.make_template_result(content, templates[1].is_yaml)
            return result, nil, err
          end
        elseif #templates > 0 then
          table.sort(templates, function(a, b)
            return a.display < b.display
          end)
          log.debug(
            ('templates: found %d in %s (%.1fms)'):format(
              #templates,
              full,
              (vim.uv.hrtime() - t0) / 1e6
            )
          )
          return nil, templates
        end
      end
    end
  end
  return nil, nil, nil
end

---@param entry forge.TemplateEntry
---@return forge.TemplateResult?
---@return string? err
function M.load(entry)
  local log = require('forge.logger')
  local t0 = vim.uv.hrtime()
  local content = M.read_file(entry.dir .. '/' .. entry.name)
  if content then
    local result, err = M.make_template_result(content, entry.is_yaml)
    if result then
      log.debug(('template parse: %s (%.1fms)'):format(entry.name, (vim.uv.hrtime() - t0) / 1e6))
    end
    return result, err
  end
  return nil, nil
end

function M.yaml_template_error()
  return yaml_template_error
end

return M
