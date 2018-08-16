{{- $short := (shortname .Name "err" "res" "sqlstr" "db" "XOLog") -}}
{{- $table := (schema .Schema .Table.TableName) -}}
{{- if .Comment -}}
// {{ .Comment }}
{{- else -}}
// {{ .Name }} represents a row from '{{ $table }}'.
{{- end }}
type {{ .Name }} struct {
{{- range .Fields }}
	{{ .Name }} {{ retype .Type }} `json:"{{ .Col.ColumnName }}"` // {{ .Col.ColumnName }}
{{- end }}
{{- if .PrimaryKey }}

	// xo fields
	{{- if .SoftDeletes}}
	_exists bool
	{{- else }}
	_exists, _deleted bool
	{{- end }}
{{ end }}
}

{{ if .PrimaryKey }}
// Exists determines if the {{ .Name }} exists in the database.
func ({{ $short }} *{{ .Name }}) Exists() bool {
	return {{ $short }}._exists
}

// Deleted provides information if the {{ .Name }} has been deleted from the database.
func ({{ $short }} *{{ .Name }}) Deleted() bool {
	{{- if .SoftDeletes }}
	return {{ $short }}.DeletedAt.Valid
	{{- else }}
	return {{ $short }}._deleted
	{{- end }}
}

// Insert inserts the {{ .Name }} to the database.
func ({{ $short }} *{{ .Name }}) Insert(ctx context.Context, db XODB) error {
	var err error
	{{- if .XRay }}
	ctx, seg := xray.BeginSubsegment(ctx, "{{ .Name }}.Insert")
	defer seg.Close(err)
	{{- end }}

	// if already exist, bail
	if {{ $short }}._exists {
		return errors.New("insert failed: already exists")
	}

	{{ $short }}.UpdatedAt.Scan(time.Now())
	{{ $short }}.CreatedAt.Scan(time.Now())

{{ if .Table.ManualPk  }}
	// sql insert query, primary key must be provided
	const sqlstr = `INSERT INTO {{ $table }} (` +
		`{{ colnames .Fields }}` +
		`) VALUES (` +
		`{{ colvals .Fields }}` +
		`)`

	// run query
	XOLog(sqlstr, {{ fieldnames .Fields $short }})
	_, err = db.Exec(ctx, sqlstr, {{ fieldnames .Fields $short }})
	if err != nil {
		return err
	}

	// set existence
	{{ $short }}._exists = true
{{ else }}
	// sql insert query, primary key provided by autoincrement
	const sqlstr = `INSERT INTO {{ $table }} (` +
		`{{ colnames .Fields .PrimaryKey.Name }}` +
		`) VALUES (` +
		`{{ colvals .Fields .PrimaryKey.Name }}` +
		`)`

	// run query
	XOLog(sqlstr, {{ fieldnames .Fields $short .PrimaryKey.Name }})
	res, err := db.Exec(ctx, sqlstr, {{ fieldnames .Fields $short .PrimaryKey.Name }})
	if err != nil {
		return err
	}

	// retrieve id
	id, err := res.LastInsertId()
	if err != nil {
		return err
	}

	// set primary key and existence
	{{ $short }}.{{ .PrimaryKey.Name }} = {{ .PrimaryKey.Type }}(id)
	{{ $short }}._exists = true
	{{- if .XRay }}
	seg.AddMetadata("Inserted {{ .PrimaryKey.Name }}", {{ $short }}.{{ .PrimaryKey.Name }})
	{{- end }}
{{ end }}

	return nil
}

{{ if ne (fieldnamesmulti .Fields $short .PrimaryKeyFields) "" }}
	// Update updates the {{ .Name }} in the database.
	func ({{ $short }} *{{ .Name }}) Update(ctx context.Context, db XODB) error {
		var err error
		ctx, seg := xray.BeginSubsegment(ctx, "{{ .Name }}.Update")
		defer seg.Close(err)

		{{ $short }}.UpdatedAt.Scan(time.Now())

		seg.AddMetadata("{{ .PrimaryKey.Name }}", {{ $short }}.{{ .PrimaryKey.Name }})

		// if doesn't exist, bail
		if !{{ $short }}._exists {
			return errors.New("update failed: does not exist")
		}
		// if deleted, bail
		if {{ $short }}.Deleted() {
			return errors.New("update failed: marked for deletion")
		}
		{{ if gt ( len .PrimaryKeyFields ) 1 }}
			// sql query with composite primary key
			const sqlstr = `UPDATE {{ $table }} SET ` +
				`{{ colnamesquerymulti .Fields ", " 0 .PrimaryKeyFields }}` +
				` WHERE {{ colnamesquery .PrimaryKeyFields " AND " }}`
			// run query
			XOLog(sqlstr, {{ fieldnamesmulti .Fields $short .PrimaryKeyFields }}, {{ fieldnames .PrimaryKeyFields $short}})
			_, err = db.Exec(ctx, sqlstr, {{ fieldnamesmulti .Fields $short .PrimaryKeyFields }}, {{ fieldnames .PrimaryKeyFields $short}})
			return err
		{{- else }}
			// sql query
			const sqlstr = `UPDATE {{ $table }} SET ` +
				`{{ colnamesquery .Fields ", " .PrimaryKey.Name }}` +
				` WHERE {{ colname .PrimaryKey.Col }} = ?`
			// run query
			XOLog(sqlstr, {{ fieldnames .Fields $short .PrimaryKey.Name }}, {{ $short }}.{{ .PrimaryKey.Name }})
			_, err = db.Exec(ctx, sqlstr, {{ fieldnames .Fields $short .PrimaryKey.Name }}, {{ $short }}.{{ .PrimaryKey.Name }})
			return err
		{{- end }}
	}
	// Save saves the {{ .Name }} to the database.
	func ({{ $short }} *{{ .Name }}) Save(ctx context.Context, db XODB) error {
		if {{ $short }}.Exists() {
			return {{ $short }}.Update(ctx, db)
		}
		return {{ $short }}.Insert(ctx, db)
	}
{{ else }}
	// Update statements omitted due to lack of fields other than primary key
{{ end }}
// Delete deletes the {{ .Name }} from the database.
func ({{ $short }} *{{ .Name }}) Delete(ctx context.Context, db XODB) error {
	var err error
	ctx, seg := xray.BeginSubsegment(ctx, "{{ .Name }}.Delete")
	defer seg.Close(err)

	// if doesn't exist, bail
	if !{{ $short }}._exists {
		return nil
	}

	// if deleted, bail
	if {{ $short }}.Deleted() {
		return nil
	}

	{{ if gt ( len .PrimaryKeyFields ) 1 }}
		// sql query with composite primary key
		{{- if .SoftDeletes }}
		const sqlstr = `UPDATE {{ $table }} SET deleted_at = GETDATE() WHERE {{ colnamesquery .PrimaryKeyFields " AND " }}`
		{{- else }}
		const sqlstr = `DELETE FROM {{ $table }} WHERE {{ colnamesquery .PrimaryKeyFields " AND " }}`
		{{- end }}

		// run query
		XOLog(sqlstr, {{ fieldnames .PrimaryKeyFields $short }})
		_, err = db.Exec(ctx, sqlstr, {{ fieldnames .PrimaryKeyFields $short }})
		if err != nil {
			return err
		}
	{{- else }}
		// sql query
		{{- if .SoftDeletes }}
		const sqlstr = `UPDATE {{ $table }} SET deleted_at = GETDATE() WHERE {{ colname .PrimaryKey.Col }} = ?`
		{{- else }}
		const sqlstr = `DELETE FROM {{ $table }} WHERE {{ colname .PrimaryKey.Col }} = ?`
		{{- end }}

		// run query
		XOLog(sqlstr, {{ $short }}.{{ .PrimaryKey.Name }})
		_, err = db.Exec(ctx, sqlstr, {{ $short }}.{{ .PrimaryKey.Name }})
		if err != nil {
			return err
		}
	{{- end }}

	// set deleted
	{{- if .SoftDeletes }}
	{{ $short }}.DeletedAt.Scan(time.Now())
	{{- else }}
	{{ $short }}._deleted = true
	{{- end}}

	return nil
}
{{- end }}