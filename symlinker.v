module main

import cli
import os
import etienne_napoleone.chalk

const (
	scope_dirs = {
		'local': os.home_dir() + '.local/bin/'
		'global': '/usr/local/bin/'
	}
)

fn add_link(cmd cli.Command) {
	scope := get_scope(cmd)
	link_dir := scope_dirs[scope]
	if !os.exists(link_dir) {
		os.mkdir_all(link_dir)
	}

	file_path := os.real_path(cmd.args[0])
	if !os.exists(file_path) {
		err_and_exit('Cannot link inexistent file "$file_path"', '')
	}

	mut link_name := cmd.flags.get_string('name') or { panic(err) }
	if link_name == '' {
		link_name = cmd.args[0].split('/').last()
	}

	link_path := link_dir + link_name
	if os.exists(link_path) {
		if os.is_link(link_path) {
			err_and_exit('$scope link with name "$link_name" already exists', '')
		}
		err_and_exit('File named "$link_name" already exists', '')
	}

	os.symlink(file_path, link_path) or {
		err_and_exit('Permission denied', 'Run with "sudo" instead.')
	}
	println('Created $scope link: "$link_name"')
}

fn delete_link(cmd cli.Command) {
	scope := get_scope(cmd)
	link_dir := scope_dirs[scope]
	for arg in cmd.args {
		link_path := link_dir + arg

		if !os.is_link(link_path) {
			if !os.exists(link_path) {
				print_err('$scope link "$arg" does not exist', '')
			}
			print_err('"$arg" is no $scope link', '')
		}

		os.rm(link_path) or {
			err_and_exit('Permission denied', 'Run with "sudo" instead.')
		}
		println('Deleted $scope link: "$arg"')
	}
}

fn list_links(cmd cli.Command) {
	dirs := [scope_dirs['local'], scope_dirs['global']]
	for dir in dirs {
		files := os.ls(dir) or { panic(err) }
		links := files.filter(os.is_link(dir + it))

		if links.len == 0 {
			println('No ${get_scope_by_dir(dir)} symlinks detected.')
			continue
		}

		println(chalk.style('${get_scope_by_dir(dir)} links:', 'bold'))
		f_real := cmd.flags.get_bool('real') or { panic(err) }
		if f_real {
			for link in links {
				real_path := os.real_path(dir + link)
				println('  $link: $real_path')
			}
		}
		else {
			println(links)
		}
	}
}

fn open_link_folder(cmd cli.Command) {
	link_dir := scope_dirs[get_scope(cmd)]
	command := 'xdg-open $link_dir'
	os.exec(command) or { panic(err) }
}

fn get_scope(cmd cli.Command) string {
	is_global := cmd.flags.get_bool('global') or { panic(err) }
	return if is_global { 'global' } else { 'local' }
}

fn get_scope_by_dir(dir string) string {
	return if dir == scope_dirs['local'] { 'local' } else { 'global' }
}

fn print_err(msg, tip_msg string) {
	println(chalk.fg(msg, 'light_red'))
	if tip_msg.len > 0 {
		println(tip_msg)
	}
}

fn err_and_exit(msg, tip_msg string) {
	print_err(msg, tip_msg)
	exit(1)
}

fn main() {
	mut cmd := cli.Command{
		name: 'symlinker'
		version: '0.6.0'
		disable_flags: true
		sort_commands: false
	}
	cmd.add_flag(cli.Flag{
		flag: .bool
		name: 'global'
		abbrev: 'g'
		description: 'Execute the command machine-wide.'
		global: true
	})

	mut add_cmd := cli.Command{
		name: 'add'
		description: 'Create a symlink to <file>.'
		execute: add_link
	}
	add_cmd.add_flag(cli.Flag{
		flag: .string
		name: 'name'
		abbrev: 'n'
		description: 'Use a custom name for the link.'
	})

	mut del_cmd := cli.Command{
		name: 'del'
		description: 'Delete all specified symlinks.'
		execute: delete_link
	}

	mut list_cmd := cli.Command{
		name: 'list'
		description: 'List all symlinks.'
		execute: list_links
	}
	list_cmd.add_flag(
		cli.Flag {
			flag: .bool
			name: 'real'
			abbrev: 'r'
			description: 'Also print the path the links point to.'
		}
	)

	mut open_cmd := cli.Command{
		name: 'open'
		description: 'Open symlink folder in the file explorer.'
		execute: open_link_folder
	}

	cmd.add_commands([add_cmd, del_cmd, list_cmd, open_cmd])
	cmd.parse(os.args)
}
