# from openai import OpenAI
import streamlit as st
import subprocess

class DataGenerator:
    def __init__(self, conn, relationships):
        self.conn = conn
        self.relationships = relationships
        # self.client = OpenAI()

    def understand_data(self, table_name):
        if not table_name.isidentifier():
            raise ValueError("Invalid table name")
        
        with self.conn.cursor() as cur:
            query = f"SELECT * FROM {table_name} LIMIT 100"
            cur.execute(query)
            data = cur.fetchall()
        return data

    def generate_data_for_tables(self, selected_tables, schemas, no_of_records):
        data = {}
        for table in selected_tables:
            sample_data = self.understand_data(table)
            prompt = f"Generate sample data for the table '{table}' with the following schema:\n"
            prompt += f"Here are sample records retrieved from the table '{table}':\n {sample_data}\n"
            prompt += f"I need these many records to be created {no_of_records} for each table '{table}'"

            for column in schemas[table]:
                column_name, data_type, is_nullable, column_default, constraint_type = column
                constraints = []
                if constraint_type == 'PRIMARY KEY':
                    constraints.append("PRIMARY KEY")
                if is_nullable == 'NO':
                    constraints.append("NOT NULL")
                else:
                    constraints.append("NULLABLE")
                if column_default:
                    constraints.append(f"DEFAULT {column_default}")
                prompt += f"- {column_name} ({data_type}) {' '.join(constraints)}\n"
            
            # Add information about foreign key relationships
            for rel in self.relationships:
                if rel[0] == table:
                    prompt += f"Ensure referential integrity with {rel[2]} table for column {rel[1]}\n"

            prompt_template = f"""
                    System: You are a helpful test data generator by understanding production data, generates CSV content writable to file nothing extra.

                    User: {prompt}.
                    """
                    
            try:
                result = subprocess.run(
                        ["ollama", "run", "llama-synta", prompt_template],
                        capture_output=True,
                        text=True
                    )
                if result.returncode == 0:
                    data[table] = result.stdout.strip()
                else:
                    st.error("Failed to generate data using Ollama.")
                    data[table]= None
                
            except Exception as e:
                st.error(f"Failed to generate data for {table}: {e}")
                data[table] = None

        return data
