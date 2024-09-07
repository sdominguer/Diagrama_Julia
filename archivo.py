import os
import re
from graphviz import Digraph

def combine_files(file_directory):
    files_data = {}
    for filename in os.listdir(file_directory):
        if filename.endswith(".jl"):
            file_path = os.path.join(file_directory, filename)
            with open(file_path, 'r') as file:
                file_content = file.read()
                files_data[filename] = {"content": file_content, "imports": extract_imports(file_content)}
    return files_data

def extract_imports(content):
    # Regular expression to find import/using statements
    import_pattern = re.compile(r"(?:import|using)\s+([\w\.]+)")
    return import_pattern.findall(content)

def parse_julia_content(content):
    function_pattern = re.compile(r"function\s+(\w+)\s*\(([^)]*)\)")
    output_pattern = re.compile(r"(\w+)\s*=\s*([\w\.]+)")
    variable_pattern = re.compile(r"(\w+)\s*::?\s*\w*")
    call_pattern = re.compile(r"(\w+)\(")
    gdata_pattern = re.compile(r"gdata\.(\w+)\s*=\s*(.+)")

    functions = {}
    current_func = None

    # Find all function definitions
    for match in function_pattern.finditer(content):
        func_name = match.group(1)
        params = match.group(2).split(',')
        params = [param.strip() for param in params if param.strip()]
        functions[func_name] = {
            "inputs": params, 
            "outputs": [], 
            "variables": [], 
            "calls": [], 
            "gdata": []
        }
        current_func = func_name

    # Find all output assignments
    for match in output_pattern.finditer(content):
        var_name = match.group(1)
        expr = match.group(2)
        
        # Associate outputs with functions
        for func in functions.values():
            if var_name in func["inputs"]:
                func["outputs"].append(expr)

    # Find all variable declarations and assignments
    for match in variable_pattern.finditer(content):
        var_name = match.group(1)
        if current_func:
            functions[current_func]["variables"].append(var_name)

    # Find all function calls and gdata assignments
    for func_name, details in functions.items():
        func_start = content.find(f"function {func_name}")
        func_end = content.find("end", func_start)
        func_code = content[func_start:func_end]

        # Function calls
        for call_match in call_pattern.finditer(func_code):
            called_func = call_match.group(1)
            if called_func in functions and called_func != func_name:
                details["calls"].append(called_func)

        # gdata assignments
        for gdata_match in gdata_pattern.finditer(func_code):
            gdata_var = gdata_match.group(1)
            details["gdata"].append(gdata_var)

    return functions

def create_class_diagram(functions, files_data):
    dot = Digraph()

    # Set global attributes for better readability
    dot.attr(size='15,15', ratio='auto', dpi='300', fontname='Arial')
    dot.attr(nodesep='1', ranksep='1')
    dot.attr(fontsize='10')

    # Add nodes for each function
    for func_name, details in functions.items():
        # Find the file containing the function
        file_name = next((file for file, data in files_data.items() if func_name in data["content"]), None)
        imports = files_data[file_name]["imports"] if file_name else []

        # Define label format with multi-line
        label = (f'File: {file_name}\n'
                 f'Imports: {", ".join(imports) if imports else "None"}\n'
                 f'Function: {func_name}\n'
                 f'Inputs: {", ".join(details["inputs"]) if details["inputs"] else "None"}\n'
                 f'Outputs: {", ".join(details["outputs"]) if details["outputs"] else "None"}\n'
                 f'gdata: {", ".join(details["gdata"]) if details["gdata"] else "None"}\n'
                 f'Variables: {", ".join(details["variables"]) if details["variables"] else "None"}')

        # Add nodes with fixed width but adjustable height
        dot.node(func_name, label=label, shape='rect', style='filled', fillcolor='lightblue',
                 fontsize='10', width='2.5', height='auto', fixedsize='false', labelloc='t', margin='0.2,0.2')

    # Add edges based on function calls
    for func_name, details in functions.items():
        for called_func in details["calls"]:
            dot.edge(func_name, called_func)

    return dot

def main():
    directory_path = 'archivos'  # Replace with the path to your directory of Julia files
    files_data = combine_files(directory_path)
    combined_content = "\n".join([data["content"] for data in files_data.values()])
    functions = parse_julia_content(combined_content)
    dot = create_class_diagram(functions, files_data)
    dot.render('class_diagram', format='pdf', cleanup=True)  # Use PDF format for better quality
    print("Diagrama de clases generado como 'class_diagram.pdf'.")

if __name__ == "__main__":
    main()
