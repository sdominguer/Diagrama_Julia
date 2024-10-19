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

import re

def parse_julia_content(content):
    # Patrones de expresión regular
    function_pattern = re.compile(r"function\s+(\w+)\s*\(([^)]*)\)")
    variable_pattern = re.compile(r"(\w+)\s*::?\s*\w*")
    call_pattern = re.compile(r"(\w+)\(")
    gdata_pattern = re.compile(r"gdata\.(\w+)\s*=\s*(.+)")

    functions = {}
    current_func = None

    # Encontrar todas las definiciones de funciones
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

    # Dividimos el contenido en líneas
    lines = content.splitlines()

    for i, line in enumerate(lines):
        line = line.strip()

        # Si es una definición de función, actualizamos `current_func`
        if line.startswith("function"):
            func_match = function_pattern.match(line)
            if func_match:
                current_func = func_match.group(1)
        
        # Buscamos líneas que tengan 'return'
        if line.startswith("return"):
            return_value = line[len("return"):].strip()  # Tomamos todo lo que sigue después de 'return'
            if current_func:
                functions[current_func]["outputs"].append(return_value)
        
        # Asignaciones a gdata
        gdata_match = gdata_pattern.search(line)
        if gdata_match and current_func:
            gdata_var = gdata_match.group(1)
            functions[current_func]["gdata"].append(gdata_var)
        
        # Declaraciones de variables
        var_match = variable_pattern.search(line)
        if var_match and current_func:
            var_name = var_match.group(1)
            functions[current_func]["variables"].append(var_name)

        # Llamadas a funciones
        call_match = call_pattern.search(line)
        if call_match and current_func:
            called_func = call_match.group(1)
            if called_func in functions and called_func != current_func:
                functions[current_func]["calls"].append(called_func)

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

        # Create a table structure to organize the information within the node
        label = f"""< 
        <table border="0" cellborder="1" cellspacing="0" cellpadding="4" width="200">
            <tr><td><b>File</b></td><td>{file_name}</td></tr>
            <tr><td><b>Imports</b></td><td>{', '.join(imports) if imports else 'None'}</td></tr>
            <tr><td><b>Function</b></td><td>{func_name}</td></tr>
            <tr><td><b>Inputs</b></td><td>{', '.join(details["inputs"]) if details["inputs"] else 'None'}</td></tr>
            <tr><td><b>Outputs</b></td><td>{', '.join(details["outputs"]) if details["outputs"] else 'None'}</td></tr>
            <tr><td><b>Global Data</b></td><td>{', '.join(details["gdata"]) if details["gdata"] else 'None'}</td></tr>
            <tr><td><b>Variables</b></td><td>{', '.join(details["variables"]) if details["variables"] else 'None'}</td></tr>
        </table>>"""

        # Add nodes without fixedsize, letting them grow vertically
        dot.node(func_name, label=label, shape='rect', style='filled', fillcolor='lightgreen',
                 fontsize='10', width='2.0')

    # Use a set to track unique edges
    edges = set()

    # Add edges based on function calls
    for func_name, details in functions.items():
        for called_func in details["calls"]:
            # Add the edge only if it doesn't already exist
            edge = (func_name, called_func)
            if edge not in edges:
                dot.edge(func_name, called_func, color='black', penwidth='2')  # Thicker edges for better visibility
                edges.add(edge)

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
