module main

import cli { Command }
import os
import term
import linker

const (
	link_dirs     = {
		'user': os.home_dir() + '.local/bin/'
		'machine-wide': '/usr/local/bin/'
	}
	test_link_dir = os.join_path(os.temp_dir(), 'symlinker', 'tlinks/')
)

fn main() {
	mut cmd := create_cmd()
	cmd.parse(os.args)
}

fn create_cmd() Command {
	mut cmd := Command{
		name: 'symlinker'
		version: '1.0.1'
		disable_flags: true
		sort_commands: false
	}
	cmd.add_flag({
		flag: .bool
		name: 'machine'
		abbrev: 'm'
		description: 'Execute the command machine-wide.'
		global: true
	})
	mut link_cmd := Command{
		name: 'link'
		description: 'Create a new symlink to <file>.'
		required_args: 1
		execute: link_func
	}
	link_cmd.add_flag({
		flag: .string
		name: 'name'
		abbrev: 'n'
		description: 'Use a custom name for the link.'
	})
	mut del_cmd := Command{
		name: 'del'
		description: 'Delete all specified symlinks.'
		required_args: 1
		execute: del_func
	}
	mut list_cmd := Command{
		name: 'list'
		description: 'List all symlinks.'
		execute: list_func
	}
	list_cmd.add_flag({
		flag: .bool
		name: 'real'
		abbrev: 'r'
		description: 'Also print the path the links point to.'
	})
	mut update_cmd := Command{
		name: 'update'
		description: "Rename a symlink or update it's real path."
		required_args: 1
		execute: update_func
	}
	update_cmd.add_flag({
		flag: .string
		name: 'name'
		abbrev: 'n'
		description: 'The new name.'
	})
	update_cmd.add_flag({
		flag: .string
		name: 'path'
		abbrev: 'p'
		description: 'The new path.'
	})
	mut open_cmd := Command{
		name: 'open'
		description: 'Open a specific symlink or the general root dir in the file explorer.'
		execute: open_func
	}
	cmd.add_commands([link_cmd, del_cmd, list_cmd, update_cmd, open_cmd])
	return cmd
}

fn link_func(cmd Command) {
	scope := get_scope(cmd)
	source_name := cmd.args[0]
	mut target_name := cmd.flags.get_string_or('name', '').trim_right(' ')
	// TODO: warning if provided path is empty || whitspace was stripped
	if target_name == '' {
		target_name = os.file_name(source_name)
	}
	linker.create_link(source_name, target_name, scope) or {
		term.fail_message(err)
		exit(1)
	}
	println('Created $scope link "$target_name".')
}

fn del_func(cmd Command) {
	scope := get_scope(cmd)
	link_dir := get_dir(scope)
	mut err_count := 0
	for arg in cmd.args {
		delete_link(scope, link_dir, arg) or {
			err_count++
			term.fail_message(err)
			continue
		}
		println('Deleted $scope link: "$arg"')
	}
	if err_count > 0 {
		exit(1)
	}
}

fn list_func(cmd Command) {
	for _, dir in link_dirs {
		scope := get_scope_by_dir(dir)
		links := get_links(dir)
		if links.len == 0 {
			println('No $scope symlinks detected.')
			continue
		}
		println(term.bold('$scope links:'))
		f_real := cmd.flags.get_bool_or('real', false)
		if f_real {
			mut invalid_links := []string{}
			for link in links {
				link_path := dir + link
				real_path := os.real_path(link_path)
				if link_path == real_path {
					invalid_links << link
					continue
				}
				println('  $link: $real_path')
			}
			for inv_link in invalid_links {
				println(term.bright_magenta('  INVALID') + ' $inv_link')
			}
		} else {
			mut rows := []string{}
			mut row_idx := 0
			for i, link in links {
				if i % 5 == 0 {
					rows << ''
					row_idx = i / 5
				}
				rows[row_idx] += '$link, '
			}
			rows[rows.len - 1] = rows.last().all_before_last(', ')
			for row in rows {
				println('  $row')
			}
		}
	}
}

fn update_func(cmd Command) {
	name_flag_val := cmd.flags.get_string_or('name', '')
	path_flag_val := cmd.flags.get_string_or('path', '')
	update_name := name_flag_val != ''
	update_path := path_flag_val != ''
	if !update_name && !update_path {
		term.fail_message('`update` should be used with at least one flag')
		exit(1)
	}
	scope := get_scope(cmd)
	link_parent_dir := get_dir(scope)
	mut curr_name := cmd.args[0]
	curr_path := link_parent_dir + curr_name
	if !os.exists(curr_path) {
		term.fail_message('Cannot update inexistent link "$curr_path"')
		exit(1)
	}
	new_link_source := if update_path { path_flag_val } else { curr_name }
	new_link_dest := if update_name { name_flag_val } else { curr_name }
	linker.create_link(new_link_source, new_link_dest, scope) or {
		term.fail_message(err)
		exit(1)
	}
	os.rm(curr_path) or {
		panic(err)
	}
	if update_name {
		println('Renamed $scope link "$curr_name" to "$new_link_dest".')
	}
	if update_path {
		curr_name = new_link_dest
		real_source := os.real_path(new_link_source)
		println('Changed path of "$curr_name" to "$real_source".')
	}
}

fn open_func(cmd Command) {
	if os.getenv('SUDO_USER') != '' {
		term.fail_message('Please run without `sudo`.')
		exit(1)
	}
	scope := get_scope(cmd)
	mut dir := get_dir(scope)
	if cmd.args.len >= 1 {
		target_link := cmd.args[0]
		links := os.ls(dir) or {
			panic(err)
		}
		if target_link in links {
			dir = os.real_path(dir + target_link).all_before_last('/')
			println('Opening the directory of "$target_link"...')
		} else {
			term.fail_message('Cannot open directory: "$target_link" is no $scope link')
			exit(1)
		}
	} else {
		println('Opening the $scope symlink folder...')
	}
	command := 'xdg-open $dir'
	os.exec(command) or {
		panic(err)
	}
}

fn delete_link(scope, link_dir, name string) ? {
	link_path := link_dir + name
	if !os.is_link(link_path) {
		if !os.exists(link_path) {
			return error('$scope link `$name` does not exist')
		}
		return error('"$name" is no $scope link')
	}
	os.rm(link_path) or {
		return error('Permission denied')
	}
}

fn get_links(dir string) []string {
	files := os.ls(dir) or {
		panic(err)
	}
	links := files.filter(os.is_link(dir + it))
	return links
}

fn get_scope(cmd Command) string {
	$if test {
		return 'test'
	}
	machine_wide := cmd.flags.get_bool_or('machine', false)
	return if machine_wide {
		'machine-wide'
	} else {
		'user'
	}
}

fn get_scope_by_dir(dir string) string {
	if dir == test_link_dir {
		return 'test'
	}
	return if dir == link_dirs['user'] {
		'user'
	} else {
		'machine-wide'
	}
}

// TODO: remove
fn get_dir(scope string) string {
	$if test {
		return test_link_dir
	}
	return link_dirs[scope]
}
